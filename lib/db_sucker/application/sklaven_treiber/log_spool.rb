module DbSucker
  class Application
    class SklavenTreiber
      class LogSpool
        attr_reader :original

        def initialize original
          @original = original
          @enabled = true
          @spool = []
          @monitor = Monitor.new
        end

        def sync
          @monitor.synchronize { yield }
        end

        def enable
          sync do
            @enabled = true
          end
        end

        def clear
          sync { @spool.clear }
        end

        def disable void_spool = false, &block
          sync do
            @enabled = false
            (void_spool && clear) || (block && spooldown(&block))
          end
        end

        def spooldown
          sync do
            while e = @spool.shift
              yield(e + [original])
            end
          end
        end

        def puts *args
          sync { @enabled ? (@spool << [:puts, args, Time.current]) : @original.puts(*args) }
        end

        def print *args
          sync { @enabled ? (@spool << [:print, args, Time.current]) : @original.print(*args) }
        end

        def warn *args
          sync { @enabled ? (@spool << [:warn, args, Time.current]) : @original.warn(*args) }
        end
      end
    end
  end
end
