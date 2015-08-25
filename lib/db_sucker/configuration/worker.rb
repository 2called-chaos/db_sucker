module DbSucker
  class Configuration
    class Worker
      include Helpers
      attr_reader :app, :id, :ctn, :var, :table

      def initialize app, id, ctn, var, table, deferred = false
        @app = app
        @id = id
        @ctn = ctn
        @var = var
        @table = table
        @status = ["idle", :black]
        @deferred = deferred

        @active = true
      end

      def active?
        @active
      end

      def identifier
        "#{id}_table"
      end

      def tmp_filename tmp_suffix = false
        "#{ctn.tmp_path}/#{id}_#{table}.dbsc#{".tmp" if tmp_suffix}"
      end

      def local_tmp_path
        "#{File.expand_path(ENV["DBS_TMPDIR"] || ENV["TMPDIR"] || "/tmp")}/db_sucker_tmp"
      end

      def local_tmp_file file
        "#{local_tmp_path}/#{file}"
      end

      def second_progress channel, status, color = :yellow, is_thread = false, initial = 0
        Thread.new do
          Thread.current.abort_on_exception = true
          Thread.current[:iteration] = initial
          loop do
            channel.close rescue false if Thread.main[:shutdown]
            stat = status.gsub(":seconds", human_seconds(Thread.current[:iteration]))
            stat = stat.gsub(":workers", channel[:workers].to_s.presence || "?") if is_thread
            if channel.closing?
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

      def sequel_progress channel
        Thread.new do
          Thread.current.abort_on_exception = true
          Thread.current[:iteration] = 0
          loop do
            if instance = channel[:importer]
              instance.abort rescue false if Thread.main[:shutdown]
              if instance.closing?
                @status = ["[CLOSING] #{instance.progress}", :red]
              else
                @status = [instance.progress, :yellow]
              end
              break unless instance.active?
            else
              @status = ["initializing sequel importer...", :yellow]
            end
            sleep 1
            Thread.current[:iteration] += 1
          end
        end
      end

      def may_interrupt
        stat = @status[0].to_s.gsub("[CLOSING]", "").strip
        @status = ["[CLOSED] #{stat}", :black]
        raise Interrupt if Thread.main[:shutdown]
      end

      def colored_status
        !@active && runtime ? ["#{@status[0]} (#{runtime})", @status[1]] : @status
      end

      def runtime
        if @started && @ended
          human_seconds (@ended - @started).to_i
        end
      end

      def start
        perform = @deferred ? %w[deferred_import] : %w[dump_file rename_file compress_file download_file copy_file decompress_file import_file]
        @started = Time.current
        @status = ["initializing...", :yellow]
        @download_state = { state: :idle, offset: 0 }
        @files_to_remove = []
        @local_files_to_remove = []
        Thread.new {
          begin
            may_interrupt

            perform.each do |m|
              send(:"_#{m}")
              may_interrupt
            end

            @status = ["DONE", :green]
            sleep 1
          rescue StandardError => ex
            @status = ["ERROR (#{ex.class}): #{ex.message} (was #{@status[0]})", :red]
            sleep 5
          ensure
            # cleanup temp files
            ctn.sftp_start do |sftp|
              @files_to_remove.each do |file|
                sftp.remove!(file) rescue false
              end
            end if @files_to_remove.any?

            # cleanup local temp files
            @local_files_to_remove.each do |file|
              File.unlink(file) rescue false
            end

            @ended = Time.current
            @active = false
          end
        }
      end

      # ===============
      # = Subroutines =
      # ===============

      def _dump_file
        @status = ["dumping table to remote file...", :yellow]
        @rfile, cr = var.dump_to_remote(self, false)
        @files_to_remove << @rfile
        @ffile = @rfile[0..-5]
        channel, result = cr
        second_progress(channel, "dumping table to remote file (:seconds)...").join
      end

      def _rename_file
        @status = ["finalizing dump process...", :yellow]
        ctn.sftp_start do |sftp|
          sftp.rename!(@rfile, @ffile)
        end
        @files_to_remove.delete(@rfile)
        @files_to_remove << @ffile
      end

      def _compress_file
        @status = ["compressing file for transfer...", :yellow]
        @cfile, cr = var.compress_file(@ffile, false)
        @files_to_remove << @cfile
        channel, result = cr
        second_progress(channel, "compressing file for transfer (:seconds)...").join
        @files_to_remove.delete(@ffile)
      end

      def _download_file
        @status = ["initiating download...", :yellow]
        @lfile = local_tmp_file(File.basename(@cfile))
        @local_files_to_remove << @lfile

        fs = 0
        ctn.sftp_start do |sftp|
          fs = sftp.lstat!(@cfile).size
        end

        # download progress display
        dpd = Thread.new do
          Thread.current.abort_on_exception = true
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
      end

      def _copy_file
        # @status = ["copying file to backup path...", :yellow]
        # bfile, cr = var.copy_file(lfile, false)
        # channel, result = cr
        # second_progress(channel, "copying file to backup path (:seconds)...").join
        # @files_to_remove.delete(ffile)
      end

      def _decompress_file
        @status = ["decompressing file...", :yellow]
        @ldfile, channel = var.decompress_file(@lfile)
        @local_files_to_remove << @ldfile
        second_progress(channel, "decompressing file (:seconds)...").join
        @local_files_to_remove.delete(@lfile)
      end

      def _import_file
        @status = ["loading file into local SQL server...", :yellow]
        if File.size(@ldfile) > 50_000_000 && app.opts[:deferred_import]
          @local_files_to_remove.delete(@ldfile)
          $deferred_import << [id, ctn, var, table, @ldfile]
          @status = ["Deferring import of large file (#{human_filesize(File.size(@ldfile))})...", :green]
          sleep 3
        else
          _do_import_file(@ldfile)
        end
      end

      def _do_import_file(file, deferred = false)
        $importing.synchronize { $importing << self }
        var.load_local_file(self, file) do |importer, channel|
          case importer
            when "sequel" then sequel_progress(channel).join
            else second_progress(channel, "#{"(deferred) " if deferred}loading file (#{human_filesize(File.size(file))}) into local SQL server (:seconds)...").join
          end
        end
      ensure
        $importing.synchronize { $importing.delete(self) }
      end

      def _deferred_import
        @local_files_to_remove << @deferred

        # ==================================
        # = Wait for other workers to exit =
        # ==================================
        @status = ["waiting for other workers...", :blue]
        wchannel = var.wait_for_workers
        twc = second_progress(wchannel, "waiting for :workers other workers (:seconds)...", :blue, true)
        twc.join
        may_interrupt

        # =================
        # = Aquiring lock =
        # =================
        @status = ["waiting for deferred import lock...", :blue]
        @locked = false

        progress_thread = Thread.new do
          t = var.channelfy_thread(Thread.new{ sleep 1 until @locked })
          second_progress(t, "waiting for deferred import lock (:seconds)...", :blue, false, twc[:iteration]).join
        end

        $deferred_importer.synchronize do
          @locked = true
          progress_thread.join
          may_interrupt

          # ===============================
          # = Import file to local server =
          # ===============================
          @status = ["(deferred) loading file into local SQL server...", :yellow]
          _do_import_file(@deferred, true)
        end
      end
    end
  end
end
