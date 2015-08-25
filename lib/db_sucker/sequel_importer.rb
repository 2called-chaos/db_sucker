module DbSucker
  class SequelImporter
    attr_reader :worker, :file, :started

    def initialize(worker, file)
      @worker = worker
      @file = file
      @active = false
      @closing = false
    end

    def start
      @started = Time.current
      @active = true
      sleep 10
    ensure
      @active = false
    end

    def progress
      "#{runtime}"
    end

    def runtime
      worker.human_seconds ((@ended || Time.current) - @started).to_i
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
  end
end
