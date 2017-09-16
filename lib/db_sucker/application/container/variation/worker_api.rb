module DbSucker
  class Application
    class Container
      class Variation
        module WorkerApi
          def tables_to_transfer
            all = cfg.table_list(cfg.data["source"]["database"]).map(&:first)
            keep = []
            if data["only"]
              [*data["only"]].each do |t|
                unless all.include?(t)
                  raise TableNotFoundError, "table `#{t}' for the database `#{cfg.source["database"]}' could not be found (provided by variation `#{cfg.name}/#{name}' in `#{cfg.src}')"
                end
                keep << t
              end
            elsif data["except"]
              keep = all.dup
              [*data["except"]].each do |t|
                unless all.include?(t)
                  raise TableNotFoundError, "table `#{t}' for the database `#{cfg.source["database"]}' could not be found (provided by variation `#{cfg.name}/#{name}' in `#{cfg.src}')"
                end
                keep.delete(t)
              end
            else
              keep = all.dup
            end
            keep -= data["ignore_always"] if data["ignore_always"].is_a?(Array)

            [keep, all]
          end

          def dump_to_remote_command worker, pv_binary = false
            tmpfile = worker.tmp_filename(true)
            cmd = dump_command_for(worker.table)
            if pv_binary.presence
              cmd << %{ | #{pv_binary} -n -b > #{tmpfile}}
            else
              cmd << %{ > #{tmpfile}}
            end
            [tmpfile, cmd]
          end

          def dump_to_remote worker, blocking = true
            tfile, cmd = dump_to_remote_command(worker)
            [tfile, cfg.blocking_channel_result(cmd, channel: true, use_sh: true, blocking: blocking)]
          end

          def compress_file_command file, pv_binary = false
            if pv_binary.presence
              cmd = %{#{pv_binary} -n -b #{file} | #{gzip_binary} > #{file}.gz && rm #{file} }
            else
              cmd = %{#{gzip_binary} #{file}}
            end
            ["#{file}.gz", cmd]
          end

          def compress_file file, blocking = true
            nfile, cmd = compress_file_command(file)
            [nfile, cfg.blocking_channel_result(cmd, channel: true, use_sh: true, blocking: blocking)]
          end

          def calculate_local_integrity_hash file, blocking = true
            return unless integrity?
            cmd = "#{integrity} #{file}"
            [cmd, local_execute(cmd, thread: !blocking, blocking: blocking, close_stdin: true)]
          end

          def wait_for_workers
            channelfy_thread Thread.new {
              loop do
                Thread.current[:workers] = $importing.synchronize { $importing.length }
                break if Thread.current[:workers] == 0
                sleep 1
              end
            }
          end

          # def load_local_file worker, file, &block
          #   imp = data["importer"]
          #   impf = parse_flags(data["importer_flags"])

          #   if imp == "void10"
          #     t = channelfy_thread Thread.new{ sleep 10 }
          #   elsif imp == "sequel" || constraint(worker.table)
          #     raise NotImplementedError, "SequelImporter is not yet implemented/ported to new db_sucker version!"
          #     # imp_was_sequel = imp == "sequel"
          #     # imp = "sequel"
          #     # t = channelfy_thread Thread.new {
          #     #   Thread.current[:importer] = imp = SequelImporter.new(worker, file, ignore_errors: !imp_was_sequel)
          #     #   imp.start
          #     # }
          #   elsif imp == "binary"
          #     t = channelfy_thread Thread.new{
          #       cmd = load_command_for(file, impf.merge(dirty: impf[:dirty] && worker.deferred))
          #       Open3.popen2e(cmd, pgroup: true) do |_ipc_stdin, _ipc_stdouterr, _ipc_thread|
          #         outerr, exit_status = _ipc_stdouterr.read, _ipc_thread.value
          #         if exit_status != 0
          #           Thread.current[:error_message] = outerr.strip
          #           sleep 3
          #         end
          #       end
          #     }
          #   else
          #     raise ImporterNotFoundError, "variation `#{cfg.name}/#{name}' defines unknown importer `#{imp}' (in `#{cfg.src}')"
          #   end

          #   block.call(imp, t)
          # end

          # def dump_to_local_stream
          #   raise NotImplemented
          # end
        end
      end
    end
  end
end
