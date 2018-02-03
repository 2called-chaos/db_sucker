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
        end
      end
    end
  end
end
