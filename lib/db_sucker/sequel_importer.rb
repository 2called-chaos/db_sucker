module DbSucker
  class SequelImporter
    include Helpers
    include Application::LoggerClient
    BUFFER_SIZE = 1000
    POOL_SIZE   = 6
    attr_reader :worker, :file, :started, :status, :error

    def initialize(worker, file, opt = {})
      @opt = opt.reverse_merge(ignore_errors: false)
      @worker = worker
      @file = file
      @active = false
      @closing = false
      @status = ["", :yellow]
      @error = nil
    end

    def _init
      @started = Time.current
      @active = true
      @filesize = File.size(file)
      @workers = []

      # stats
      @stat = { loaded_bytes: 0, loaded: 0, executed_bytes: 0, executed: 0, succeeded: 0, failed: 0 }
      @stat.extend(MonitorMixin)

      # buffer
      @buf = []
      @buf.extend(MonitorMixin)
      @unprocessed = 0
      @icond = @buf.new_cond
      @pcond = @buf.new_cond
      @econd = @buf.new_cond
    end

    def start
      _init
      establish_db_connection
      spool_file_to_buf
      spawn_workers(POOL_SIZE)
      wait_for_eof_file
      wait_for_exit
      Thread.current[:return_message] = pstat
      sleep 1
    rescue StandardError => ex
      @error = ex
    ensure
      @active = false
    end

    def establish_db_connection
      @db = Sequel.connect(dsn, max_connections: POOL_SIZE)
      @db.run("SELECT version()")
    end

    def spool_file_to_buf
      @spool = Thread.new do
        File.open(@file).each_line do |l|
          if @closing
            @buf.synchronize { @pcond.signal }
            break
          end
          @stat.synchronize do
            @stat[:loaded] += 1
            @stat[:loaded_bytes] += l.bytesize
          end
          @buf.synchronize do
            @buf << l
            @unprocessed += 1
            @pcond.signal
            @icond.wait_until { @unprocessed < BUFFER_SIZE }
          end
        end
        @buf.synchronize { @pcond.signal }
      end
    end

    def spawn_workers num
      while @workers.length < num
        @workers << Thread.new {
          loop do
            if @closing
              @buf.synchronize {
                @icond.signal
                @pcond.signal
              }
              break
            end
            line = @buf.synchronize { @buf.shift unless @buf.empty? } rescue false

            if line
              success = false
              if line.start_with?("INSERT")
                begin
                  @db.run(line)
                  success = true
                rescue StandardError => ex
                  raise ex unless @opt[:ignore_errors]
                end
              end

              @stat.synchronize do
                @stat[:executed] += 1
                @stat[:executed_bytes] += line.bytesize
                @stat[success ? :succeeded : :failed] += 1
              end

              # update queue
              @buf.synchronize {
                @unprocessed -= 1
                @icond.signal
                @econd.signal
              }
            else
              break if !@spool.alive?
              @buf.synchronize { @pcond.wait_until { !@spool.alive? || @unprocessed > 0 } }
            end
          end
        }
      end
    end

    def wait_for_eof_file
      @spool.join
    end

    def wait_for_exit
      @buf.synchronize {
        @econd.wait_until { @closing || @unprocessed.zero? }
        @pcond.signal
      }
      @workers.each(&:join)
    end

    def abort
      @closing = true
    end

    def closing?
      @closing
    end

    def active?
      @active
    end

    def progress
      if @error
        ["ERROR (#{@error.class}): #{@error.message}", :red]
      else
        tags = []
        tags << "*R" if @spool && @spool.alive?
        tags << "E" if @workers && @workers.any?(&:alive?)
        perc = f_percentage(@stat[:loaded_bytes], @filesize)
        eperc = f_percentage(@stat[:executed_bytes], @filesize)

        stat = "".tap do |s|
          s << "[#{tags.join("")}] " if tags.any?
          s << "#{perc} loaded – "
          s << "#{eperc} executed "
          s << c("(SP:#{@unprocessed}/#{BUFFER_SIZE})", :cyan)
          s << "#{c " – "}#{pstat} "
          s << c("(#{runtime})")
        end
        [stat, :yellow]
      end
    end

    def pstat
      "#{c @stat[:succeeded], :green}#{c "/"}#{c @stat[:failed], :red}#{c "/"}#{c @stat[:executed], :white}"
    end

    def runtime
      worker.human_seconds ((@ended || Time.current) - @started).to_i
    end

    def dsn
      d = worker.var.data
      "mysql2://".tap do |r|
        r << d["username"] if d["username"]
        r << ":#{d["password"]}" if d["password"]
        r << "@#{d["hostname"]}" if d["hostname"]
        r << ":#{d["port"]}" if d["port"]
        r << "/#{d["database"]}" if d["database"]
      end
    end
  end
end
