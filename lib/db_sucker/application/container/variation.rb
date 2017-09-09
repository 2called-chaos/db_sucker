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

        # =============
        # = Accessors =
        # =============

        def ctn
          cfg
        end

        def source
          ctn.source
        end

        def label
          data["label"]
        end

        def incrementals
          data["incremental"] || {}
        end

        def gzip_binary
          source["gzip_binary"] || "gzip"
        end

        def integrity
          (data["integrity"].nil? ? "shasum -ba512" : data["integrity"]).presence
        end

        def integrity?
          ctn.integrity? && integrity
        end

        def copies_file?
          data["file"]
        end

        def copies_file_compressed?
          copies_file? && data["file"].end_with?(".gz")
        end

        def requires_uncompression?
          !copies_file_compressed? || data["database"]
        end

        # ===========
        # = RPC API =
        # ===========

        [
          :client_binary,
          :local_client_binary,
          :dump_binary,
          :client_call,
          :local_client_call,
          :dump_call,
          :database_list,
          :table_list,
          :hostname,
        ].each do |meth|
          define_method meth do
            raise NotImplementedError, "Your adapter `#{@data["adapter"]}' (used in `#{cfg.src}') must implement `##{meth}'"
          end
        end

        def dump_command_for table
          raise NotImplementedError, "Your adapter `#{@data["adapter"]}' (used in `#{cfg.src}') must implement `#dump_command_for(table)'"
        end


        # ====================
        # = Internal helpers =
        # ====================
        def parse_flags flags
          flags.to_s.split(" ").map(&:strip).reject(&:blank?).each_with_object({}) do |fstr, res|
            if m = fstr.match(/\+(?<key>[^=]+)(?:=(?<value>))?/)
              res[m[:key].strip] = m[:value].nil? ? true : m[:value]
            elsif m = fstr.match(/\-(?<key>[^=]+)/)
              res[m[:key]] = false
            else
              raise "invalid importer_flag `#{fstr}' for variation `#{cfg.name}/#{name}' in #{cfg.src}"
            end
          end
        end

        def channelfy_thread thr
          def thr.active?
            alive?
          end

          def thr.closed?
            alive?
          end

          def thr.closing?
            !alive?
          end

          thr
        end

        def local_execute cmd, opts = {}
          opts = opts.reverse_merge(blocking: true, thread: false, close_stdin: false, close_stdouterr: false)
          result = []
          thr = channelfy_thread Thread.new {
            Open3.popen2e(cmd, pgroup: true) do |_ipc_stdin, _ipc_stdouterr, _ipc_thread|
              Thread.current[:ipc_thread] = _ipc_thread
              Thread.current[:ipc_stdin] = _ipc_stdin
              Thread.current[:ipc_stdouterr] = _ipc_stdouterr
              _ipc_stdin.close if opts[:close_stdin]
              _ipc_stdouterr.close if opts[:close_stdouterr]
              while l = _ipc_stdouterr.gets
                result << l.chomp
              end
              Thread.current[:exit_code] = _ipc_thread.value
              if Thread.current[:exit_code] != 0
                Thread.current[:error_message] = "#{result.last.try(:strip)} (exit #{Thread.current[:exit_code]})".strip
                sleep 3
              end
            end
          }
          thr.join if opts[:blocking]
          opts[:thread] ? [thr, result] : result
        end


        # ===============
        # = API methods =
        # ===============
        def tables_to_transfer
          all = cfg.table_list(cfg.data["source"]["database"]).map(&:first)
          keep = []
          if data["only"]
            [*data["only"]].each do |t|
              raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
              keep << t
            end
          elsif data["except"]
            keep = all.dup
            [*data["except"]].each do |t|
              raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
              keep.delete(t)
            end
          else
            keep = all.dup
          end
          keep -= data["ignore_always"] if data["ignore_always"].is_a?(Array)

          [keep, all]
        end

        def constraint table
          data["constraints"] && (data["constraints"][table] || data["constraints"]["__default"])
        end

        def dump_to_remote worker, blocking = true
          cmd = dump_command_for(worker.table)
          cmd << " > #{worker.tmp_filename(true)}"
          [worker.tmp_filename(true), cfg.blocking_channel_result(cmd, channel: true, request_pty: true, blocking: blocking)]
        end

        def compress_file file, blocking = true
          cmd = %{#{gzip_binary} #{file}}
          ["#{file}.gz", cfg.blocking_channel_result(cmd, channel: true, request_pty: true, blocking: blocking)]
        end

        def calculate_local_integrity_hash file, blocking = true
          return unless integrity?
          cmd = "#{integrity} #{file}"
          [cmd, local_execute(cmd, thread: !blocking, blocking: blocking, close_stdin: true)]
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

        def load_local_file worker, file, &block
          imp = data["importer"]
          impf = parse_flags(data["importer_flags"])

          if imp == "void10"
            t = channelfy_thread Thread.new{ sleep 10 }
          elsif imp == "sequel" || constraint(worker.table)
            raise NotImplementedError, "SequelImporter is not yet implemented/ported to new db_sucker version!"
            # imp_was_sequel = imp == "sequel"
            # imp = "sequel"
            # t = channelfy_thread Thread.new {
            #   Thread.current[:importer] = imp = SequelImporter.new(worker, file, ignore_errors: !imp_was_sequel)
            #   imp.start
            # }
          elsif imp == "binary"
            t = channelfy_thread Thread.new{
              cmd = load_command_for(file, impf.merge(dirty: impf[:dirty] && worker.deferred))
              Open3.popen2e(cmd, pgroup: true) do |_ipc_stdin, _ipc_stdouterr, _ipc_thread|
                outerr, exit_status = _ipc_stdouterr.read, _ipc_thread.value
                if exit_status != 0
                  Thread.current[:error_message] = outerr.strip
                  sleep 3
                end
              end
            }
          else
            raise "unknown importer `#{imp}' for variation `#{cfg.name}/#{name}' in #{cfg.src}"
          end

          block.call(imp, t)
        end

        def dump_to_local_stream
          raise NotImplemented
        end
      end
    end
  end
end
