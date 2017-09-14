module DbSucker
  class Application
    class SklavenTreiber
      class LogSpool
        def initialize
          @spool = []
          @monitor = Monitor.new
        end

        def sync
          @monitor.synchronize { yield }
        end

        def spooldown
          sync do
            while e = @spool.shift
              yield(e)
            end
          end
        end

        def puts *args
          sync { @spool << [:puts, args, Time.current] }
        end

        def print *args
          sync { @spool << [:print, args, Time.current] }
        end

        def warn *args
          sync { @spool << [:warn, args, Time.current] }
        end
      end
    end
  end
end
