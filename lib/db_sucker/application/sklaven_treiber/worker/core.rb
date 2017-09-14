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

          def cancel! reason = nil, now = false
            @should_cancel = reason || true
            sync { _cancelpoint(reason) if pending? || now }
          end

          def _cancelpoint reason = nil
            if @should_cancel
              reason ||= @should_cancel if @should_cancel.is_a?(String)
              reason ||= @status[0]
              @should_cancel = false
              @state = :canceled
              @status = ["CANCELED#{" (was #{reason.to_s.gsub("[CLOSING] ", "")})" if reason}", "red"]
              throw :abort_execution, true
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
                _cancelpoint
                @step = i + 1
                r = catch(:abort_execution) {
                  begin
                    r0 = Time.current
                    send(:"_#{m}")
                  ensure
                    @timings[m] = Time.current - r0
                  end
                  nil
                }
                throw :abort_execution if r
                _cancelpoint
              end
              @status = ["DONE (#{runtime})", "green"]
            end
          rescue StandardError => ex
            @exception = ex
            @status = ["FAILED(#{current_perform}) #{ex.class}: #{ex.message}", "red"]
            @state = :failed
            Thread.main[:app].notify_exception("SklavenTreiber::Worker encountered an error in `#{current_perform}' (ctn: #{ctn.name}, var: #{var.name}, db: #{ctn.source["database"]}, table: #{table})", ex)
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

            @state = :done if !canceled? && !failed?
            @ended = Time.current

            # debug timings
            debug "[Timings(#{table})] all: #{human_seconds(@timings.values.sum, 3)}, #{@timings.map{|a,t| "#{a}: #{human_seconds(t, 3)}" } * ", "}", 50
          end
        end
      end
    end
  end
end
