module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        include Core
        include Accessors
        include Helpers
        include Routines

        attr_reader :exception, :ctn, :var, :table, :thread, :monitor, :step, :perform, :should_cancel, :sklaventreiber
        OutputHelper.hook(self)

        def initialize sklaventreiber, ctn, var, table
          @sklaventreiber = sklaventreiber
          @ctn = ctn
          @var = var
          @table = table
          @monitor = Monitor.new
          @perform = %w[].tap do |perform|
            perform << "r_dump_file"
            perform << "r_calculate_raw_hash" if ctn.integrity?
            perform << "r_compress_file"
            perform << "r_calculate_compressed_hash" if ctn.integrity?
            perform << "l_download_file"
            perform << "l_verify_compressed_hash" if ctn.integrity?
            perform << "l_copy_file" if var.data["file"]
            if var.requires_uncompression?
              perform << "l_decompress_file"
              perform << "l_verify_raw_hash" if ctn.integrity?
              perform << "l_import_file" if var.data["database"]
            end
          end

          @state = :pending
          @status = ["waiting...", "gray"]
        end
      end
    end
  end
end
