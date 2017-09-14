module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        include Core
        include Accessors
        include Helpers
        include Routines

        attr_reader :exception, :ctn, :var, :table, :thread, :monitor, :step, :perform, :should_cancel, :sklaventreiber, :timings, :sshing
        OutputHelper.hook(self)

        def initialize sklaventreiber, ctn, var, table
          @sklaventreiber = sklaventreiber
          @ctn = ctn
          @var = var
          @table = table
          @monitor = Monitor.new
          @timings = {}
          @perform = %w[].tap do |perform|
            perform << "r_dump_file"                                                                  # PV status (bytes + seconds)
            perform << "r_calculate_raw_hash" if ctn.integrity?                                       # PV status
            perform << "r_compress_file"                                                              # --------- DONE! (has pv + sec-fallback)
            perform << "r_calculate_compressed_hash" if ctn.integrity?                                # PV status
            perform << "l_download_file"                                                              # --------- DONE! (always full status)
            perform << "l_verify_compressed_hash" if ctn.integrity?                                   # PV status? we would need local PV or we lockin on SHA and do it with ruby locally
            perform << "l_copy_file" if var.copies_file? && var.copies_file_compressed?               # --------- DONE! (always full status)
            if var.requires_uncompression?                                                            # ---------
              perform << "l_decompress_file"                                                          # --------- DONE! (always full status)
              perform << "l_verify_raw_hash" if ctn.integrity?                                        # PV status? we would need local PV or we lockin on SHA and do it with ruby locally
              perform << "l_copy_file" if var.copies_file? && !var.copies_file_compressed?            # --------- DONE! (always full status)
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
