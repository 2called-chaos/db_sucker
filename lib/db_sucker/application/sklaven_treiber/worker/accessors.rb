module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Accessors
          def pending?
            @state == :pending
          end

          def done?
            succeeded? || failed? || canceled?
          end

          def failed?
            @state == :failed
          end

          def succeeded?
            @state == :done
          end

          def canceled?
            @state == :canceled
          end

          def running?
            @state == :running
          end

          def status
            @status
          end

          def state
            @state
          end

          def trxid
            @sklaventreiber.trxid
          end

          def descriptive
            "#{ctn.source_database}-#{table}"
          end

          def identifier
            "#{trxid}_table"
          end

          def tmp_filename tmp_suffix = false
            "#{ctn.tmp_path}/#{trxid}_#{ctn.source_database}_#{table}.dbsc#{".tmp" if tmp_suffix}"
          end

          def local_tmp_path
            @sklaventreiber.app.core_tmp_path
          end

          def local_tmp_file file
            "#{local_tmp_path}/#{file}"
          end
        end
      end
    end
  end
end
