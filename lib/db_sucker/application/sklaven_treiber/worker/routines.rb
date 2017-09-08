module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Routines
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

            ctn.sftp_start do |sftp|
              sftp.rename!(@rfile, @ffile)
            end
            @remote_files_to_remove.delete(@rfile)
            @remote_files_to_remove << @ffile
          end

          def _compress_file
            @status = ["compressing file for transfer...", "yellow"]

            @cfile, cr = var.compress_file(@ffile, false)
            @remote_files_to_remove << @cfile
            channel, result = cr
            second_progress(channel, "compressing file for transfer (:seconds)...").join
            @remote_files_to_remove.delete(@ffile) unless @should_cancel
          end

          def _download_file
            @status = ["initiating download...", "yellow"]
            @lfile = local_tmp_file(File.basename(@cfile))
            @local_files_to_remove << @lfile

            sftp_download(@ctn, @cfile => @lfile) do |dl|
              dl.status_format = :full
              @status = [dl, "yellow"]
              dl.abort_if { @should_cancel }
              dl.download!
            end
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
