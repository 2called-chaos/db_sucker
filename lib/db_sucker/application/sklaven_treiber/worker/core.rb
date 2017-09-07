module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Core
          def sync
            @monitor.synchronize { yield }
          end

          def aquire thread
            @thread = thread
            if m = thread[:managed_worker]
              debug "Consumer thread ##{m} aquired worker #{descriptive}"
            else
              debug "Main thread aquired worker #{descriptive}"
            end
            @status = ["initializing...", "gray"]
            @state = :aquired
            self
          end

          def cancel! reason = nil
            @should_cancel = reason || true
            sync { _cancelpoint if pending? }
          end

          def _cancelpoint reason = nil, abort = false
            if @should_cancel
              reason ||= @should_cancel if @should_cancel.is_a?(String)
              @should_cancel = false
              @state = :canceled
              @status = ["CANCELED#{" (was #{reason})" if reason}", "red"]
              throw :abort_execution, true if abort
              true
            end
          end

          def priority
            100 - ({
              running: 50,
              aquired: 50,
              canceled: 35,
              pending: 30,
              failed: 20,
              done: 10,
            }[@state] || 0)
          end

          def run
            @state = :running
            @started = Time.current
            @download_state = { state: :idle, offset: 0 }
            @remote_files_to_remove = []
            @local_files_to_remove = []
            current_perform = nil

            catch :abort_execution do
              perform.each_with_index do |m, i|
                current_perform = m
                _cancelpoint @status[0], true
                @step = i + 1
                send(:"_#{m}")
              end
              @status = ["DONE (#{runtime})", "green"]
            end
          rescue StandardError => ex
            @exception = ex
            @status = ["FAILED (#{ex.message})", "red"]
            @state = :failed
            Thread.main[:app].sync do
              error "SklavenTreiber::Worker encountered an error in `#{current_perform}' (ctn: #{ctn.name}, var: #{var.name}, db: #{ctn.source_database}, table: #{table})"
              warn c("\t#{ex.class}: #{ex.message}", :red)
              ex.backtrace.each{|l| warn c("\t  #{l}", :red) }
            end
          ensure
            # cleanup temp files
            ctn.sftp_start do |sftp|
              @remote_files_to_remove.each do |file|
                sftp.remove!(file) rescue false
              end
            end if @remote_files_to_remove.any?

            # cleanup local temp files
            @local_files_to_remove.each do |file|
              File.unlink(file) rescue false
            end

            @ended = Time.current
            @state = :done if !canceled? && !failed?
          end
        end
      end
    end
  end
end
