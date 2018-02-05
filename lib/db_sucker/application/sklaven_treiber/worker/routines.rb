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
            label = "verifying compressed file"
            @status = ["#{label}...", :yellow]

            file_shasum(@ctn, @local_file_compressed) do |fc|
              fc.label = label
              fc.sha = ctn.integrity_sha
              fc.status_format = app.opts[:status_format]
              @status = [fc, "yellow"]

              fc.abort_if { @should_cancel }
              fc.on_success do
                @integrity[:compressed_local] = fc.result
              end
              fc.verify!
            end


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
            label = "verifying raw file"
            @status = ["#{label}...", :yellow]

            file_shasum(@ctn, @local_file_raw) do |fc|
              fc.label = label
              fc.sha = ctn.integrity_sha
              fc.status_format = app.opts[:status_format]
              @status = [fc, "yellow"]

              fc.abort_if { @should_cancel }
              fc.on_success do
                @integrity[:raw_local] = fc.result
              end
              fc.verify!
            end

            if !@should_cancel && @integrity[:raw] != @integrity[:raw_local]
              @status = ["[INTEGRITY] extracted raw file corrupted! (remote: #{@integrity[:raw]}, local: #{@integrity[:raw_local]})", :red]
              throw :abort_execution, true
            end
          end

          def _l_import_file
            if File.size(@local_file_raw) > app.opts[:deferred_threshold] && app.opts[:deferred_import]
              @deferred = true
              @perform << "l_wait_for_workers"
            else
              # cancel!("importing not yet implemented", true)
              _do_import_file
            end
          end

          def _l_wait_for_workers
            @perform << "l_import_file_deferred"
            wait_defer_ready
          end

          def _l_import_file_deferred
            @status = ["importing #{human_bytes(File.size(@local_file_raw))} SQL data into local server...", :yellow]
            _do_import_file
          end

          def _do_import_file
            @status = ["importing #{human_bytes(File.size(@local_file_raw))} SQL data into local server...", :yellow]

            imp = @var.data["importer"]
            impf = @var.parse_flags(var.data["importer_flags"]).merge(deferred: @deferred)

            if imp == "void10"
              t = app.channelfy_thread app.spawn_thread(:sklaventreiber_worker_io_import_sql) {|thr| thr.wait(10) }
              second_progress(t, "importing with void10, sleeping 10 seconds (:seconds)...").join
            elsif imp == "sequel" || @var.constraint(table)
              raise NotImplementedError, "SequelImporter is not yet implemented/ported to new db_sucker version!"
              #     # imp_was_sequel = imp == "sequel"
              #     # imp = "sequel"
              #     # t = app.channelfy_thread Thread.new {
              #     #   Thread.current[:importer] = imp = SequelImporter.new(worker, file, ignore_errors: !imp_was_sequel)
              #     #   imp.start
              #     # }
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
            elsif imp == "binary"
              t = app.channelfy_thread app.spawn_thread(:sklaventreiber_worker_io_import_sql) {|thr|
                begin
                  file_import_sql(@ctn, :instruction) do |fi|
                    @status = [fi, "yellow"]
                    fi.instruction = @var.import_instruction_for(@local_file_raw, impf)
                    fi.filesize = File.size(@local_file_raw)
                    fi.status_format = app.opts[:status_format]
                    fi.abort_if { @should_cancel }
                    fi.import!
                  end
                rescue Worker::IO::FileImportSql::ImportError => ex
                  fail! "ImportError: #{ex.message}"
                  sleep 3
                end
              }
            else
              raise ImporterNotFoundError, "variation `#{cfg.name}/#{name}' defines unknown importer `#{imp}' (in `#{cfg.src}')"
            end
            t.join
          end
        end
      end
    end
  end
end
