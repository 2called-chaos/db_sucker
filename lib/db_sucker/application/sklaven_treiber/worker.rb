module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        include Core
        include Accessors
        include Helpers
        include Routines

        attr_reader :exception, :ctn, :var, :table, :thread, :monitor, :step, :perform, :should_cancel
        OutputHelper.hook(self)

        def initialize sklaventreiber, ctn, var, table
          @sklaventreiber = sklaventreiber
          @ctn = ctn
          @var = var
          @table = table
          @monitor = Monitor.new
          @perform = %w[dump_file rename_file compress_file download_file copy_file decompress_file import_file]

          @state = :pending
          @status = ["waiting...", "gray"]
        end
      end
    end
  end
end
