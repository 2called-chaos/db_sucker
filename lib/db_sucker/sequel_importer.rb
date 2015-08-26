module DbSucker
  class SequelImporter
    attr_reader :worker, :file, :started, :status, :error

    def initialize(worker, file)
      @worker = worker
      @file = file
      @active = false
      @closing = false
      @status = ["", :yellow]
      @error = nil
    end

    def start
      @started = Time.current
      @active = true

      # establish DB connection
      @db = Sequel.connect(dsn)

      # open file

      # read file to buffer

      # execute from buffer

      # dataset = @db['select id from products']
      # `say #{dataset.count}` # will return the number of records in the result set
      # dataset.map(:id) # will return an array containing all values of the id column in the result set

      sleep 10
    rescue StandardError => ex
      @error = ex
    ensure
      @active = false
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
        ["#{runtime}", :yellow]
      end
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
