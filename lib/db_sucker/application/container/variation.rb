module DbSucker
  class Application
    class Container
      class Variation
        attr_reader :cfg, :name, :data

        def initialize cfg, name, data
          @cfg, @name, @data = cfg, name, data

          if data["base"]
            bdata = cfg.variation(data["base"]) || raise("variation `#{name}' cannot base from `#{data["base"]}' since it doesn't exist (in `#{cfg.src}')")
            @data = data.reverse_merge(bdata.data)
          end

          if @data["adapter"]
            begin
              extend "DbSucker::Adapters::#{@data["adapter"].camelize}::RPC".constantize
            rescue NameError => ex
              raise(ex, "variation `#{name}' defines invalid adapter `#{@data["adapter"]}' (in `#{cfg.src}'): #{ex.message}", ex.backtrace)
            end
          else
            raise("variation `#{name}' must define an adapter to use (in `#{cfg.src}')")
          end
        end

        def label
          data["label"]
        end

        def incrementals
          data["incremental"] || {}
        end

        def tables_to_transfer
          all = cfg.table_list(cfg.data["source"]["database"]).map(&:first)
          keep = []
          if data["only"]
            [*data["only"]].each do |t|
              raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
              keep << t
            end
          elsif data["except"]
            keep = all
            [*data["except"]].each do |t|
              raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
              keep.delete(t)
            end
          else
            keep = all
          end
          keep -= data["ignore_always"] if data["ignore_always"].is_a?(Array)

          [keep, all]
        end

        def constraint table
          data["constraints"] && (data["constraints"][table] || data["constraints"]["__default"])
        end

        def dump_command_for table
          [].tap do |r|
            r << "mysqldump"
            r << "-h#{cfg.data["source"]["hostname"]}" unless cfg.data["source"]["hostname"].blank?
            r << "-u#{cfg.data["source"]["username"]}" unless cfg.data["source"]["username"].blank?
            r << "-p#{cfg.data["source"]["password"]}" unless cfg.data["source"]["password"].blank?
            if c = constraint(table)
              r << "--compact --skip-extended-insert --no-create-info --complete-insert"
              r << Shellwords.escape("-w#{c}")
            end
            r << cfg.data["source"]["database"]
            r << table
            r << "#{cfg.data["source"]["args"]}"
          end.join(" ")
        end

        def load_command_for file, dirty = false
          base = [].tap do |r|
            r << "mysql"
            r << "-h#{data["hostname"]}" unless data["hostname"].blank?
            r << "-u#{data["username"]}" unless data["username"].blank?
            r << "-p#{data["password"]}" unless data["password"].blank?
            r << data["database"]
            r << "#{data["args"]}"
          end.join(" ")

          if dirty
            %{
              (
                echo "SET AUTOCOMMIT=0;"
                echo "SET UNIQUE_CHECKS=0;"
                echo "SET FOREIGN_KEY_CHECKS=0;"
                cat #{file}
                echo "SET FOREIGN_KEY_CHECKS=1;"
                echo "SET UNIQUE_CHECKS=1;"
                echo "SET AUTOCOMMIT=1;"
                echo "COMMIT;"
              ) | #{base}
            }
          else
            "#{base} < #{file}"
          end
        end

        def dump_to_remote worker, blocking = true
          cmd = dump_command_for(worker.table)
          cmd << " > #{worker.tmp_filename(true)}"
          [worker.tmp_filename(true), cfg.blocking_channel_result(cmd, channel: true, blocking: blocking)]
        end

        def compress_file file, blocking = true
          cmd = %{gzip #{file}}
          ["#{file}.gz", cfg.blocking_channel_result(cmd, channel: true, blocking: blocking)]
        end

        def channelfy_thread t
          def t.active?
            alive?
          end

          def t.closed?
            alive?
          end

          def t.closing?
            !alive?
          end

          t
        end

        def decompress_file file
          cmd = %{gunzip #{file}}
          t = channelfy_thread(Thread.new{ system("#{cmd}") })
          [file[0..-4], t]
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

        def transfer_remote_to_local remote_file, local_file, blocking = true, &block
          FileUtils.mkdir_p(File.dirname(local_file))
          cfg.sftp_start(true) do |sftp|
            sftp.download!(remote_file, local_file, read_size: 5 * 1024 * 1024, &block)
          end
        end

        def load_local_file worker, file, &block
          imp = data["importer"]
          if imp == "void10"
            t = channelfy_thread Thread.new{ sleep 10 }
          elsif imp == "sequel" || constraint(worker.table)
            imp_was_sequel = imp == "sequel"
            imp = "sequel"
            t = channelfy_thread Thread.new {
              Thread.current[:importer] = imp = SequelImporter.new(worker, file, ignore_errors: !imp_was_sequel)
              imp.start
            }
          else
            t = channelfy_thread Thread.new{
              cmd = load_command_for(file, imp == "dirty" && worker.deferred)
              Open3.popen2e(cmd, pgroup: true) do |_ipc_stdin, _ipc_stdouterr, _ipc_thread|
                outerr, exit_status = _ipc_stdouterr.read, _ipc_thread.value
                if exit_status != 0
                  Thread.current[:error_message] = outerr.strip
                  sleep 3
                end
              end
            }
          end

          block.call(imp, t)
        end

        def copy_file worker, srcfile
          d, dt = Time.current.strftime("%Y-%m-%d"), Time.current.strftime("%H-%M-%S")
          bfile = data["file"]
          bfile = bfile.gsub(":combined", ":datetime_-_:table")
          bfile = bfile.gsub(":datetime", "#{d}_#{dt}")
          bfile = bfile.gsub(":date", d)
          bfile = bfile.gsub(":time", dt)
          bfile = bfile.gsub(":table", worker.table)
          bfile = bfile.gsub(":id", worker.id)
          bfile = File.expand_path(bfile)
          bfile = "#{bfile}.gz" if data["gzip"] && !bfile.end_with?(".gz")
          bfile = bfile[0..-4] if !data["gzip"] && bfile.end_with?(".gz")
          t = Thread.new{
            FileUtils.mkdir_p(File.dirname(bfile))
            FileUtils.copy_file(srcfile, bfile)
          }
          [bfile, channelfy_thread(t)]
        end

        def dump_to_local_stream
          raise NotImplemented
        end
      end
    end
  end
end
