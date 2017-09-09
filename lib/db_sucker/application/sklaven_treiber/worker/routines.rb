module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Routines
          def _dump_file
            @status = ["dumping table to remote file...", "yellow"]

            @remote_file_raw_tmp, cr = var.dump_to_remote(self, false)
            @remote_files_to_remove << @remote_file_raw_tmp
            @remote_file_raw = @remote_file_raw_tmp[0..-5]
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
              sftp.rename!(@remote_file_raw_tmp, @remote_file_raw)
            end
            @remote_files_to_remove.delete(@remote_file_raw_tmp)
            @remote_files_to_remove << @remote_file_raw
          end

          def _compress_file
            @status = ["compressing file for transfer...", "yellow"]

            @remote_file_compressed, cr = var.compress_file(@remote_file_raw, false)
            @remote_files_to_remove << @remote_file_compressed
            channel, result = cr
            second_progress(channel, "compressing file for transfer (:seconds)...").join
            @remote_files_to_remove.delete(@remote_file_raw) unless @should_cancel
          end

          def _download_file
            @status = ["initiating download...", "yellow"]
            @local_file_compressed = local_tmp_file(File.basename(@remote_file_compressed))
            @local_files_to_remove << @local_file_compressed

            sftp_download(@ctn, @remote_file_compressed => @local_file_compressed) do |dl|
              dl.status_format = :full
              @status = [dl, "yellow"]
              dl.abort_if { @should_cancel }
              dl.download!
            end
          end

          def _copy_file file = nil
            if var.data["file"].is_a?(String)
              if !var.data["file"].end_with?(".gz") && !@delay_copy_file
                @delay_copy_file = true
                return
              end
              label = "copying #{@delay_copy_file ? "raw" : "gzipped"} file"
              @status = ["#{label}...", :yellow]

              @copy_file_source = file || @local_file_compressed
              @copy_file_target = copy_file_destination(@copy_file_source, var.data["file"])

              file_copy(@ctn, @copy_file_source => @copy_file_target) do |fc|
                fc.label = label
                fc.status_format = :full
                @status = [fc, "yellow"]
                fc.abort_if { @should_cancel }
                fc.copy!
              end
            end
          end

          def _decompress_file
            @status = ["decompressing file...", "yellow"]
            sleep 3
            return

            @local_file_raw, channel = var.decompress_file(@local_file_compressed)
            @local_files_to_remove << @local_file_raw
            second_progress(channel, "decompressing file (:seconds)...").join
            @local_files_to_remove.delete(@local_file_compressed)
            _copy_file(@local_file_raw) if @delay_copy_file
          end

          def _import_file
            if var.data["database"]
              @status = ["loading file into local SQL server...", "yellow"]
              sleep 3
              return

              if File.size(@local_file_raw) > 50_000_000 && app.opts[:deferred_import]
                @local_files_to_remove.delete(@local_file_raw)
                $deferred_import << [id, ctn, var, table, @local_file_raw]
                @status = ["Deferring import of large file (#{human_filesize(File.size(@local_file_raw))})...", :green]
                @got_deferred = true
                sleep 3
              else
                _do_import_file(@local_file_raw)
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
