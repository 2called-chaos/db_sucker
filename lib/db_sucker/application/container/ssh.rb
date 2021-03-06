module DbSucker
  class Application
    class Container
      module SSH
        CommandExecutionError = Class.new(::RuntimeError)
        ChannelOpenFailedError = Class.new(::RuntimeError)

        begin # SSH
          def ssh_begin
            debug "Opening SSH connection for identifier `#{name}'"
            @ssh = ssh_start
            begin
              yield(@ssh)
            ensure
              ssh_end
            end if block_given?
          end

          def ssh_end
            return unless @ssh
            debug "Closing SSH connection for identifier `#{name}'"
            @ssh.try(:close) rescue false
            debug "CLOSED SSH connection for identifier `#{name}'"
            @ssh = nil
          end

          def ssh_sync &block
            @ssh_mutex.synchronize(&block)
          end

          def ssh_start new_connection = false, &block
            if @ssh && !new_connection
              ssh_sync do
                debug "Reusing SSH connection in start for identifier `#{name}'"
                return block ? block.call(@ssh) : @ssh
              end
            end
            debug "Opening new SSH connection in start for identifier `#{name}'"

            opt = {}
            opt[:user] = source["ssh"]["username"] if source["ssh"]["username"].present?
            opt[:password] = source["ssh"]["password"] if source["ssh"]["password"].present?
            opt[:keys] = ssh_key_files if ssh_key_files.any?
            opt[:port] = source["ssh"]["port"] if source["ssh"]["port"].present?
            if block
              Net::SSH.start(source["ssh"]["hostname"], nil, opt) do |ssh|
                block.call(ssh)
              end
            else
              Net::SSH.start(source["ssh"]["hostname"], nil, opt)
            end
          end
        end

        begin # SFTP
          def sftp_begin
            debug "Opening SFTP connection for identifier `#{name}'"
            @sftp = sftp_start
            begin
              yield(@sftp)
            ensure
              sftp_end
            end if block_given?
          end

          def sftp_end
            return unless @sftp
            debug "Closing SFTP connection for identifier `#{name}'"
            @sftp.try(:close) rescue false
            debug "CLOSED SFTP connection for identifier `#{name}'"
            @sftp = nil
          end

          def sftp_sync &block
            @sftp_mutex.synchronize(&block)
          end

          def sftp_start new_connection = false, &block
            if @sftp && !new_connection
              sftp_sync do
                debug "Reusing SFTP connection in start for identifier `#{name}'"
                return block ? block.call(@sftp) : @sftp
              end
            end
            debug "Opening new SFTP connection in start for identifier `#{name}'"

            opt = {}
            opt[:user] = source["ssh"]["username"] if source["ssh"]["username"].present?
            opt[:password] = source["ssh"]["password"] if source["ssh"]["password"].present?
            opt[:keys] = ssh_key_files if ssh_key_files.any?
            opt[:port] = source["ssh"]["port"] if source["ssh"]["port"].present?
            if block
              Net::SFTP.start(source["ssh"]["hostname"], nil, opt) do |sftp|
                block.call(sftp)
              end
            else
              Net::SFTP.start(source["ssh"]["hostname"], nil, opt)
            end
          end
        end

        begin # SSH helpers
          def loop_ssh *args, &block
            return false unless @ssh
            @ssh.loop(*args, &block)
          end

          def blocking_channel ssh = nil, result = nil, &block
            waitlock = Queue.new
            (ssh || ssh_start).open_channel do |ch|
              waitlock.pop
              block.call(ch)
            end.tap do |ch|
              # catch open_fail errors
              ch.on_open_failed do |_ch, code, desc|
                result.try(:close!)
                _ch[:open_failed] = true
                raise ChannelOpenFailedError, "#{code}: #{desc}"
              end

              ch[:wait_monitor] = Monitor.new
              ch[:wait_condition] = ch[:wait_monitor].new_cond
              st = app.sklaventreiber
              waitlock << true
              if !ssh && st && st.sync{ st.try(:poll) }
                ch[:wait_monitor].synchronize do
                  ch[:wait_condition].wait(0.1) while ch.active?
                end
              else
                ch.wait
              end
            end
          end

          def nonblocking_channel ssh = nil, result = nil, &block
            (ssh || ssh_start).open_channel do |ch|
              ch[:wait_monitor] = Monitor.new
              ch[:wait_condition] = ch[:wait_monitor].new_cond
              block.call(ch)
            end.tap do |ch|
              # catch open_fail errors
              ch.on_open_failed do |_ch, code, desc|
                result.try(:close!)
                _ch[:open_failed] = true
                raise ChannelOpenFailedError, "#{code}: #{desc}"
              end
            end
          end

          def kill_remote_process pid, sig = :INT
            ssh_start(true) do |ssh|
              blocking_channel_result("kill -#{sig} -#{pid}", ssh: ssh)
            end
          end

          def blocking_channel_result cmd, opts = {}
            opts = opts.reverse_merge(ssh: nil, blocking: true, channel: false, request_pty: false, use_sh: false)
            if opts[:use_sh]
              cmd = %{/bin/sh -c 'echo $(ps -o pgid= $$ | grep -o [0-9]*) && #{cmd}'}
              pid_monitor = Monitor.new
              pid_signal = pid_monitor.new_cond
            end
            result = EventedResultset.new
            chan = send(opts[:blocking] ? :blocking_channel : :nonblocking_channel, opts[:ssh], result) do |ch|
              chproc = ->(ch, cmd, result) {
                ch.exec(cmd) do |ch, success|
                  Thread.main[:app].debug "START: #{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{cmd} #{success}"
                  raise CommandExecutionError, "could not execute command" unless success

                  # "on_data" is called when the process writes something to stdout
                  ch.on_data do |c, data|
                    Thread.main[:app].debug "#{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{Time.current.to_f}: STDOUT: #{data}".chomp
                    if opts[:use_sh] && result.empty?
                      ch[:pid] = data.to_i
                      ch[:pid] = false if ch[:pid].zero?
                      pid_monitor.synchronize { pid_signal.broadcast } if opts[:use_sh]
                      next
                    end
                    result.enq(data, :stdout)
                  end

                  # "on_extended_data" is called when the process writes something to stderr
                  ch.on_extended_data do |c, type, data|
                    Thread.main[:app].debug "#{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{Time.current.to_f}: STDERR: #{data}".chomp
                    result.enq(data, :stderr)
                  end

                  ch.on_request "exit-status" do |ch, data|
                    Thread.main[:app].debug "#{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{Time.current.to_f}: EXIT: #{data.read_long} #{cmd}".chomp
                  end

                  ch.on_close do |ch|
                    ch[:wait_monitor].synchronize { ch[:wait_condition].broadcast }
                    Thread.main[:app].debug "#{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{Time.current.to_f}: CLOSED: #{cmd}".chomp
                  end

                  ch.on_eof do
                    Thread.main[:app].debug "#{Thread.current == Thread.main ? :main : Thread.current[:itype]}-#{Time.current.to_f}: EOF: #{cmd}".chomp
                    result.close!
                    ch[:handler].try(:signal)
                  end
                end
              }
              if opts[:request_pty]
                ch.request_pty do |ch, success|
                  raise CommandExecutionError, "could not obtain pty" unless success
                  ch[:pty] = true
                  chproc.call(ch, cmd, result)
                end
              else
                chproc.call(ch, cmd, result)
              end
            end
            pid_monitor.synchronize { pid_signal.wait(1) if !chan[:pid] } if opts[:use_sh]
            opts[:channel] ? [chan, result] : result
          end

          def nonblocking_channel_result cmd, opts = {}
            blocking_channel_result(cmd, opts.merge(blocking: false))
          end
        end
      end
    end
  end
end
