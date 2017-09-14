module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class PvWrapper < Base
            NoCommandError = Class.new(::ArgumentError)
            attr_writer :filesize
            attr_accessor :cmd, :result

            def init
              @enabled ||= Proc.new {}
              @fallback ||= Proc.new {}
              @cmd ||= @local
            end

            def enabled &block
              @enabled = block
            end

            def fallback &block
              @fallback = block
            end

            def perform! opts = {}
              if @ctn.pv_utility
                @enabled.call(@ctn.pv_utility)
                if @cmd.present?
                  begin
                    _perform_with_wrapper
                    @state = :done
                    @on_success.call(self) if !@closing && !@worker.should_cancel
                  rescue StandardError => ex
                    @operror = "#{ex.class}: #{ex.message}"
                    @on_error.call(self, ex, @operror)
                    sleep 3
                    raise
                  ensure
                    @on_complete.call(self)
                  end
                else
                  raise NoCommandError, "no command was provided, set `pv.cmd = mycmd' in the enabled callback"
                end
              else
                begin
                  @fallback.call
                  @on_success.call(self) if !@closing && !@worker.should_cancel
                rescue StandardError => ex
                  @on_error.call(self, ex, @operror)
                  raise
                ensure
                  @on_complete.call(self)
                end
              end
            end

            def _perform_with_wrapper
              reset_state
              @state = :working
              channel, @result = @ctn.nonblocking_channel_result(cmd, channel: true, use_sh: true)

              killer = Thread.new do
                Thread.current[:itype] = :sklaventreiber_worker_io_pv_killer
                loop do
                  if @worker.should_cancel && !Thread.current[:canceled]
                    channel.send_data("\C-c") rescue false if channel.is_a?(Net::SSH::Connection::Channel) && channel[:pty]
                    @ctn.kill_remote_process(channel[:pid]) if channel.is_a?(Net::SSH::Connection::Channel) && channel[:pid]
                    channel.close rescue false
                    Thread.current[:canceled] = true
                  end
                  break unless channel.active?
                  sleep 0.1
                end
              end

              @result.each_linex do |grp, line|
                next unless grp == :stderr
                @offset = line.to_i
              end
              killer.join
            end
          end
        end
      end
    end
  end
end
