module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Routines
          def _r_dump_file
            @status = ["dumping table to remote file...", "yellow"]

            pv_wrap(@ctn, nil) do |pv|
              pv.enabled do |pvbinary|
                pv.filesize = -1
                pv.label = "dumping table"
                pv.entity = "table dump"
                pv.status_format = app.opts[:status_format]
                pv.mode = :nofs
                @status = [pv, "yellow"]
                pv.abort_if { @should_cancel }

                @remote_file_raw_tmp, pv.cmd = var.dump_to_remote_command(self, pvbinary)
              end

              pv.fallback do
                @remote_file_raw_tmp, (channel, result) = var.dump_to_remote(self, false)
                second_progress(channel, "dumping table to remote file (:seconds)...").join
              end

              pv.on_complete do
                @remote_files_to_remove << @remote_file_raw_tmp
              end

              pv.perform!
            end
            _cancelpoint

            # check if response has any sort of errors and abort
            # if result.any?
            #   r = result.join
            #   if m = r.match(/(Unknown column '(.+)') in .+ \(([0-9]+)\)/i)
            #     @status = ["[DUMP] Failed: #{m[1]} (#{m[3]})", :red]
            #     throw :abort_execution, true
            #   end
            # end

            @remote_file_raw = @remote_file_raw_tmp[0..-5]
            ctn.sftp_start do |sftp|
              # rename tmp file
              sftp.rename!(@remote_file_raw_tmp, @remote_file_raw)

              # save size for gzip progress
              @remote_file_raw_filesize = sftp.lstat!(@remote_file_raw).size
            end

            @remote_files_to_remove.delete(@remote_file_raw_tmp)
            @remote_files_to_remove << @remote_file_raw
          end

          def _r_calculate_raw_hash
            @status = ["calculating integrity hash for raw file...", "yellow"]

            pv_wrap(@ctn, nil) do |pv|
              pv.enabled do |pvbinary|
                pv.filesize = @remote_file_raw_filesize
                pv.label = "hashing raw file"
                pv.entity = "hashing raw file"
                pv.status_format = app.opts[:status_format]
                @status = [pv, "yellow"]
                pv.abort_if { @should_cancel }
                pv.cmd = ctn.calculate_remote_integrity_hash_command(@remote_file_raw, pvbinary)
              end

              pv.fallback do
                cmd, (channel, pv.result) = ctn.calculate_remote_integrity_hash(@remote_file_raw, false)
                second_progress(channel, "calculating integrity hash for raw file (:seconds)...").join
              end

              pv.on_success do
                @integrity = { raw: pv.result.for_group(:stdout).join.split(" ").first.try(:strip).presence }
              end

              pv.perform!
            end
          end

          def _r_compress_file
            @status = ["compressing file for transfer...", "yellow"]

            pv_wrap(@ctn, nil) do |pv|
              pv.enabled do |pvbinary|
                pv.filesize = @remote_file_raw_filesize
                pv.label = "compressing"
                pv.entity = "compress"
                pv.status_format = app.opts[:status_format]
                @status = [pv, "yellow"]
                pv.abort_if { @should_cancel }
                @remote_file_compressed, pv.cmd = var.compress_file_command(@remote_file_raw, pvbinary)
                @remote_files_to_remove << @remote_file_compressed
              end

              pv.fallback do
                @remote_file_compressed, (channel, result) = var.compress_file(@remote_file_raw, false)
                @remote_files_to_remove << @remote_file_compressed
                second_progress(channel, "compressing file for transfer (:seconds)...").join
              end

              pv.on_success do
                @remote_files_to_remove.delete(@remote_file_raw)
              end

              pv.perform!
            end
          end

          def _r_calculate_compressed_hash
            @status = ["calculating integrity hash for compressed file...", "yellow"]

            pv_wrap(@ctn, nil) do |pv|
              pv.enabled do |pvbinary|
                pv.filesize = @remote_file_raw_filesize
                pv.label = "hashing compressed file"
                pv.entity = "hashing compressed file"
                pv.status_format = app.opts[:status_format]
                @status = [pv, "yellow"]
                pv.abort_if { @should_cancel }
                pv.cmd = ctn.calculate_remote_integrity_hash_command(@remote_file_compressed, pvbinary)
              end

              pv.fallback do
                cmd, (channel, pv.result) = ctn.calculate_remote_integrity_hash(@remote_file_compressed, false)
                second_progress(channel, "calculating integrity hash for compressed file (:seconds)...").join
              end

              pv.on_success do
                @integrity[:compressed] = pv.result.for_group(:stdout).join.split(" ").first.try(:strip).presence
              end

              pv.perform!
            end
          end

          def _l_download_file
            @status = ["initiating download...", "yellow"]
            @local_file_compressed = local_tmp_file(File.basename(@remote_file_compressed))
            @local_files_to_remove << @local_file_compressed

            sftp_download(@ctn, @remote_file_compressed => @local_file_compressed) do |dl|
              dl.status_format = app.opts[:status_format]
              @status = [dl, "yellow"]
              dl.abort_if { @should_cancel }
              dl.download!
            end
          end

          def _l_verify_compressed_hash
            return unless @integrity[:compressed]
            if !File.exist?(@local_file_compressed)
              @status = ["[INTEGRITY] compressed file does not exist?! Fatal error!", :red]
              throw :abort_execution, true
            end
            @status = ["verifying data integrity for compressed file...", "yellow"]
            cmd, (channel, result) = var.calculate_local_integrity_hash(@local_file_compressed, false)
            second_progress(channel, "verifying data integrity for compressed file (:seconds)...").join
            @integrity[:compressed_local] = result.join.split(" ").first.try(:strip).presence

            if !@should_cancel && @integrity[:compressed] != @integrity[:compressed_local]
              @status = ["[INTEGRITY] downloaded compressed file corrupted! (remote: #{@integrity[:compressed]}, local: #{@integrity[:compressed_local]})", :red]
              throw :abort_execution, true
            end
          end

          def _l_copy_file file = nil
            label = "copying #{var.copies_file_compressed? ? "gzipped" : "raw"} file"
            @status = ["#{label}...", :yellow]

            @copy_file_source = var.copies_file_compressed? ? @local_file_compressed : @local_file_raw
            @copy_file_target = copy_file_destination(var.data["file"])

            file_copy(@ctn, @copy_file_source => @copy_file_target) do |fc|
              fc.label = label
              fc.status_format = app.opts[:status_format]
              fc.integrity do |f|
                var.calculate_local_integrity_hash(f)[1].join.split(" ").first.try(:strip).presence
              end if var.integrity?
              @status = [fc, "yellow"]
              fc.abort_if { @should_cancel }
              fc.copy!
            end
          end

          def _l_decompress_file
            label = "decompressing file"
            @status = ["#{label}...", :yellow]

            file_gunzip(@ctn, @local_file_compressed) do |fc|
              fc.filesize = @remote_file_raw_filesize
              fc.label = label
              fc.status_format = app.opts[:status_format]
              @status = [fc, "yellow"]

              fc.abort_if { @should_cancel }
              fc.on_success do
                @local_files_to_remove.delete(@local_file_compressed)
                @local_file_raw = fc.local
                @local_files_to_remove << @local_file_raw
              end
              fc.gunzip!
            end
          end

          def _l_verify_raw_hash
            return unless @integrity[:raw]
            if !File.exist?(@local_file_raw)
              @status = ["[INTEGRITY] extracted raw file does not exist?! Fatal error!", :red]
              throw :abort_execution, true
            end
            @status = ["verifying data integrity for raw file...", "yellow"]
            cmd, (channel, result) = var.calculate_local_integrity_hash(@local_file_raw, false)
            second_progress(channel, "verifying data integrity for raw file (:seconds)...").join
            @integrity[:raw_local] = result.join.split(" ").first.try(:strip).presence

            if !@should_cancel && @integrity[:raw] != @integrity[:raw_local]
              @status = ["[INTEGRITY] extracted raw file corrupted! (remote: #{@integrity[:raw]}, local: #{@integrity[:raw_local]})", :red]
              throw :abort_execution, true
            end
          end

          def _l_import_file
            cancel!("importing not yet implemented", true)
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
