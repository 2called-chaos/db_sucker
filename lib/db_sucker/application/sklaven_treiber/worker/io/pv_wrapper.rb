module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class PvWrapper < Base
            NoCommandError = Class.new(::ArgumentError)
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
                raise(NoCommandError, "no command was provided, set `pv.cmd = mycmd' in the enabled callback") if @cmd.blank?
                execute(opts.slice(:tries).merge(sleep_error: 3)) do
                  _perform_with_wrapper
                end
              else
                execute(opts.slice(:tries), &@fallback)
              end
            end

            def _perform_with_wrapper
              @state = :working
              channel, @result = @ctn.nonblocking_channel_result(cmd, channel: true, use_sh: true)

              killer = @worker.app.spawn_thread(:sklaventreiber_worker_io_pv_killer) do |thr|
                loop do
                  if @worker.should_cancel && !thr[:canceled]
                    if channel.is_a?(Net::SSH::Connection::Channel)
                      if channel[:pty]
                        channel.send_data("\C-c") rescue false
                      elsif channel[:pid]
                        @ctn.kill_remote_process(channel[:pid])
                      end
                    end
                    channel.close rescue false
                    thr[:canceled] = true
                  end
                  break unless channel.active?
                  thr.wait(0.1)
                end
              end

              @result.each_linex do |grp, line|
                next unless grp == :stderr
                @offset = line.to_i
              end
              killer.signal.join
            end
          end
        end
      end
    end
  end
end
