module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        attr_reader :exception, :ctn, :var, :table, :thread, :monitor, :step, :perform
        OutputHelper.hook(self)

        def initialize sklaventreiber, ctn, var, table
          @sklaventreiber = sklaventreiber
          @ctn = ctn
          @var = var
          @table = table
          @monitor = Monitor.new
          @perform = %w[dump_file rename_file compress_file download_file copy_file decompress_file import_file]

          @state = :pending
          @status = ["waiting...", "gray"]
        end

        begin # Core
          def sync
            @monitor.synchronize { yield }
          end

          def aquire thread
            @thread = thread
            if m = thread[:managed_worker]
              debug "Consumer thread ##{m} aquired worker #{descriptive}"
            else
              debug "Main thread aquired worker #{descriptive}"
            end
            @status = ["initializing...", "gray"]
            @state = :aquired
            self
          end

          def run
            @state = :running
            @started = Time.current
            @download_state = { state: :idle, offset: 0 }
            @remote_files_to_remove = []
            @local_files_to_remove = []

            catch :abort_execution do
              perform.each_with_index do |m, i|
                _cancelpoint @status[0], true
                @step = i + 1
                send(:"_#{m}")
              end
              @status = ["DONE (#{runtime})", "green"]
            end
          rescue StandardError => ex
            @exception = ex
            @status = ["FAILED (#{ex.message})", "red"]
            @state = :failed
          ensure
            # cleanup temp files
            ctn.sftp_start do |sftp|
              @remote_files_to_remove.each do |file|
                sftp.remove!(file) rescue false
              end
            end if @remote_files_to_remove.any?

            # cleanup local temp files
            @local_files_to_remove.each do |file|
              File.unlink(file) rescue false
            end

            @ended = Time.current
            @state = :done if !canceled? && !failed?
          end
        end

        begin # Status related
          def cancel! reason = nil
            @should_cancel = reason || true
            sync { _cancelpoint if pending? }
          end

          def _cancelpoint reason = nil, abort = false
            if @should_cancel
              reason ||= @should_cancel if @should_cancel.is_a?(String)
              @should_cancel = false
              @state = :canceled
              @status = ["CANCELED#{" (was #{reason})" if reason}", "red"]
              throw :abort_execution, true if abort
              true
            end
          end

          def priority
            100 - ({
              running: 50,
              aquired: 50,
              canceled: 35,
              pending: 30,
              failed: 20,
              done: 10,
            }[@state] || 0)
          end

          def pending?
            @state == :pending
          end

          def done?
            succeeded? || failed? || canceled?
          end

          def failed?
            @state == :failed
          end

          def succeeded?
            @state == :done
          end

          def canceled?
            @state == :canceled
          end

          def running?
            @state == :running
          end

          def status
            @status
          end

          def state
            @state
          end
        end

        begin # Accessors
          def trxid
            @sklaventreiber.trxid
          end

          def identifier
            "#{trxid}_table"
          end

          def tmp_filename tmp_suffix = false
            "#{ctn.tmp_path}/#{trxid}_#{ctn.source_database}_#{table}.dbsc#{".tmp" if tmp_suffix}"
          end

          def local_tmp_path
            @sklaventreiber.app.core_tmp_path
          end

          def local_tmp_file file
            "#{local_tmp_path}/#{file}"
          end
        end

        begin # Helpers
          def descriptive
            "#{ctn.source_database}-#{table}"
          end

          def runtime
            if @started
              human_seconds ((@ended || Time.current) - @started).to_i
            end
          end

          def second_progress channel, status, color = :yellow, is_thread = false, initial = 0
            Thread.new do
              Thread.current[:iteration] = initial
              loop do
                channel.close rescue false if $core_runtime_exiting
                stat = status.gsub(":seconds", human_seconds(Thread.current[:iteration]))
                stat = stat.gsub(":workers", channel[:workers].to_s.presence || "?") if is_thread
                if channel[:error_message]
                  @status = ["[IMPORT] #{channel[:error_message]}", :red]
                elsif channel.closing?
                  @status = ["[CLOSING] #{stat}", :red]
                else
                  @status = [stat, color]
                end
                break unless channel.active?
                sleep 1
                Thread.current[:iteration] += 1
              end
            end
          end
        end

        begin # Subroutines
          def _dump_file
            @status = ["dumping table to remote file...", "yellow"]

            @rfile, cr = var.dump_to_remote(self, false)
            @remote_files_to_remove << @rfile
            @ffile = @rfile[0..-5]
            channel, result = cr
            second_progress(channel, "dumping table to remote file (:seconds)...").join

            if result.any?
              r = result.join
              if m = r.match(/(Unknown column '(.+)') in .+ \(([0-9]+)\)/i)
                @status = ["[DUMP] Failed: #{m[1]} (#{m[3]})", :red]
                throw :abort_execution
              end
            end
          end

          def _rename_file
            @status = ["finalizing dump process...", "yellow"]
            sleep 3
            return

            ctn.sftp_start do |sftp|
              sftp.rename!(@rfile, @ffile)
            end
            @remote_files_to_remove.delete(@rfile)
            @remote_files_to_remove << @ffile
          end

          def _compress_file
            @status = ["compressing file for transfer...", "yellow"]
            sleep 3
            return

            @cfile, cr = var.compress_file(@ffile, false)
            @remote_files_to_remove << @cfile
            channel, result = cr
            second_progress(channel, "compressing file for transfer (:seconds)...").join
            @remote_files_to_remove.delete(@ffile)
          end

          def _download_file
            @status = ["initiating download...", "yellow"]
            sleep 3
            return

            @lfile = local_tmp_file(File.basename(@cfile))
            @local_files_to_remove << @lfile

            fs = 0
            ctn.sftp_start do |sftp|
              fs = sftp.lstat!(@cfile).size
            end

            # download progress display
            dpd = Thread.new do
              Thread.current[:iteration] = 0
              loop do
                unless Thread.current[:suspended]
                  state = nil
                  closing = false
                  ds = @download_state
                  if Thread.main[:shutdown] && ds[:downloader]
                    ds[:downloader].abort!
                    closing = true
                  end
                  stat = case ds.try(:[], :state)
                    when nil, :idle   then "initiating download..."
                    when :init        then "starting download: #{human_filesize ds[:size]}"
                    when :downloading then "downloading: #{f_percentage(ds[:offset] || 0, ds[:size])} – #{human_filesize ds[:offset]}/#{human_filesize ds[:size]} (#{human_filesize (sp = ds[:offset] - ds[:last_offset])}/s – ETA #{sp == 0 ? "???" : human_seconds((ds[:size] - ds[:offset]) / (sp))})"
                    when :finishing   then "finishing up..."
                    when :done        then "download complete: 100% – #{human_filesize ds[:size]}"
                  end
                  ds[:last_offset] = ds[:offset]

                  @status = closing ? ["[CLOSING] #{stat}", :red] : [stat, :yellow]
                  state = ds[:state]
                  break if state == :done
                end
                sleep 1
                Thread.current[:iteration] += 1
              end
            end

            # actual download
            try = 1
            begin
              dpd[:suspended] = false
              var.transfer_remote_to_local(@cfile, @lfile) do |event, downloader, *args|
                # @download_state.synchronize do
                  case event
                  when :open then
                    @download_state[:downloader] = downloader
                    @download_state[:state] = :init
                    @download_state[:size] = fs
                  when :get then
                    @download_state[:state] = :downloading
                    @download_state[:offset] = args[1] + args[2].length
                  when :close then
                    @download_state[:state] = :finishing
                  when :finish then
                    @download_state[:state] = :done
                  else raise("unknown event #{event}#{`say #{event}`}")
                  end
                # end
              end
            rescue Net::SSH::Disconnect => ex
              dpd[:suspended] = true
              @status = ["##{try} #{ex.class}: #{ex.message}", :red]
              try += 1
              sleep 3
              if try > 4
                raise ex
              else
                dpd[:suspended] = false
                retry
              end
            end

            dpd.join
          end

          def _copy_file file = nil
            return
            if var.data["file"]
              if !var.data["gzip"] && !@delay_copy_file
                @delay_copy_file = true
                return
              end
              @status = ["copying file to target path...", :yellow]
              bfile, channel = var.copy_file(self, file || @lfile)
              second_progress(channel, "copying file to backup path (:seconds)...").join
            end
          end

          def _decompress_file
            @status = ["decompressing file...", "yellow"]
            sleep 3
            return

            @ldfile, channel = var.decompress_file(@lfile)
            @local_files_to_remove << @ldfile
            second_progress(channel, "decompressing file (:seconds)...").join
            @local_files_to_remove.delete(@lfile)
            _copy_file(@ldfile) if @delay_copy_file
          end

          def _import_file
            if var.data["database"]
              @status = ["loading file into local SQL server...", "yellow"]
              sleep 3
              return

              if File.size(@ldfile) > 50_000_000 && app.opts[:deferred_import]
                @local_files_to_remove.delete(@ldfile)
                $deferred_import << [id, ctn, var, table, @ldfile]
                @status = ["Deferring import of large file (#{human_filesize(File.size(@ldfile))})...", :green]
                @got_deferred = true
                sleep 3
              else
                _do_import_file(@ldfile)
              end
            end
          end

          # def _do_import_file(file, deferred = false)
          #   $importing.synchronize { $importing << self }
          #   var.load_local_file(self, file) do |importer, channel|
          #     case importer
          #       when "sequel"
          #         sequel_progress(channel).join
          #         if channel[:importer].error
          #           @status = ["importing with Sequel", :yellow]
          #           raise channel[:importer].error
          #         end
          #       else second_progress(channel, "#{"(deferred) " if deferred}loading file (#{human_filesize(File.size(file))}) into local SQL server (:seconds)...").join
          #     end
          #     throw :abort_execution, channel[:error_message] if channel[:error_message]
          #     @return_message = channel[:return_message] if channel[:return_message]
          #   end
          # ensure
          #   $importing.synchronize { $importing.delete(self) }
          # end

          # def _deferred_import
          #   @local_files_to_remove << @deferred

          #   # ==================================
          #   # = Wait for other workers to exit =
          #   # ==================================
          #   @status = ["waiting for other workers...", :blue]
          #   wchannel = var.wait_for_workers
          #   twc = second_progress(wchannel, "waiting for :workers other workers (:seconds)...", :blue, true)
          #   twc.join
          #   may_interrupt

          #   # =================
          #   # = Aquiring lock =
          #   # =================
          #   @status = ["waiting for deferred import lock...", :blue]
          #   @locked = false

          #   progress_thread = Thread.new do
          #     t = var.channelfy_thread(Thread.new{ sleep 1 until @locked })
          #     second_progress(t, "waiting for deferred import lock (:seconds)...", :blue, false, twc[:iteration]).join
          #   end

          #   $deferred_importer.synchronize do
          #     @locked = true
          #     progress_thread.join
          #     may_interrupt

          #     # ===============================
          #     # = Import file to local server =
          #     # ===============================
          #     @status = ["(deferred) loading file into local SQL server...", :yellow]
          #     _do_import_file(@deferred, true)
          #   end
          # end
        end
      end
    end
  end
end
