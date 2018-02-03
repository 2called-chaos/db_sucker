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
            thread[:current_task] = descriptive
            thread[:current_worker] = self
            if m = thread[:managed_worker]
              debug "Consumer thread ##{m} aquired worker #{descriptive}"
            else
              debug "Main thread aquired worker #{descriptive}"
            end
            @status = ["initializing...", "gray"]
            @state = :aquired
            self
          end

          def pause wait = false
            sync do
              return if done?
              return if @state == :pausing || @state == :paused
              @pause_data = { state_was: @state, signal: @monitor.new_cond }
              if @state == :pending
                @state = :paused
              else
                @state = :pausing
                @pause_data[:signal].wait if wait
              end
            end
          end

          def _pausepoint
            sync do
              return if !(@state == :pausing || @state == :paused)
              return unless @pause_data
              return unless @thread == Thread.current
              @state = :paused
              @pause_data[:signal].broadcast
            end
            @thread[:paused] = true
            Thread.stop
            @thread[:paused] = false
            _cancelpoint
          end

          def unpause
            sync do
              return if !(@state == :pausing || @state == :paused)
              return unless @pause_data
              @state = @pause_data[:state_was]
              @pause_data = false
              @thread.wakeup if @thread
            end
          end

          def cancel! reason = nil, now = false
            return if done?
            @should_cancel = reason || true
            unpause
            sync { _cancelpoint(reason) if pending? || now }
          end

          def fail! reason, now = false
            @status = ["FAILED(#{@current_perform}) #{reason}", "red"]
            @state = :failed
            throw :abort_execution, true if now
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
            elsif @state == :failed
              throw :abort_execution, true
              true
            end
            _pausepoint
          end

          def priority
            100 - ({
              running: 50,
              aquired: 50,
              pausing: 50,
              paused: 30,
              canceled: 35,
              pending: 30,
              failed: 20,
              done: 10,
            }[@state] || 0)
          end

          def run
            @state = :running
            @sshing = true
            @started = Time.current
            @download_state = { state: :idle, offset: 0 }
            @remote_files_to_remove = []
            @local_files_to_remove = []
            @current_perform = nil

            app.fire(:worker_routine_before_all, self)
            catch :abort_execution do
              perform.each_with_index do |m, i|
                @current_perform = m
                _cancelpoint
                @step = i + 1
                r = catch(:abort_execution) {
                  aquire_slots(*app.opts[:routine_pools][m.to_sym]) do
                    begin
                      r0 = Time.current
                      app.fire(:worker_routine_before, self, @current_perform)
                      send(:"_#{m}")
                    ensure
                      app.fire(:worker_routine_after, self, @current_perform)
                      @timings[m] = Time.current - r0
                    end
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
            fail! "#{ex.class}: #{ex.message}"
            Thread.main[:app].notify_exception("SklavenTreiber::Worker encountered an error in `#{@current_perform}' (ctn: #{ctn.name}, var: #{var.name}, db: #{ctn.source["database"]}, table: #{table})", ex)
          rescue Interrupt => ex
            @state = :failed
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

            app.fire(:worker_routine_after_all, self)
            @state = :done if !canceled? && !failed?
            @ended = Time.current
            @sshing = false

            # debug timings
            debug "[Timings(#{table})] all: #{human_seconds(@timings.values.sum, 3)}, #{@timings.map{|a,t| "#{a}: #{human_seconds(t, 3)}" } * ", "}", 50
          end
        end
      end
    end
  end
end
