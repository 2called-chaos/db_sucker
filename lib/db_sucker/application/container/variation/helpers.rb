module DbSucker
  class Application
    class Container
      class Variation
        module Helpers
          def parse_flags flags
            flags.to_s.split(" ").map(&:strip).reject(&:blank?).each_with_object({}) do |fstr, res|
              if m = fstr.match(/\+(?<key>[^=]+)(?:=(?<value>))?/)
                res[m[:key].strip] = m[:value].nil? ? true : m[:value]
              elsif m = fstr.match(/\-(?<key>[^=]+)/)
                res[m[:key]] = false
              else
                raise InvalidImporterFlagError, "invalid flag `#{fstr}' for variation `#{cfg.name}/#{name}' (in `#{cfg.src}')"
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
              Thread.current[:itype] = :sklaventreiber_worker_local_execute
              Thread.current.priority = @cfg.app.opts[:tp_sklaventreiber_worker_local_execute]
              Thread.current[:executing] = cmd
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
        end
      end
    end
  end
end
