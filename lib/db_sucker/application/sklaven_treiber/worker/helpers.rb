module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Helpers
          def runtime
            if @started
              human_seconds ((@ended || Time.current) - @started).to_i
            end
          end

          def sftp_download *args, &block
            IO::SftpDownload.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_copy *args, &block
            IO::FileCopy.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_gunzip *args, &block
            IO::FileGunzip.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_shasum *args, &block
            IO::Shasum.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def pv_wrap *args, &block
            IO::PvWrapper.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def second_progress channel, status, color = :yellow
            Thread.new do
              Thread.current[:itype] = :sklaventreiber_worker_second_progress
              Thread.current.priority = app.opts[:tp_sklaventreiber_worker_second_progress]
              Thread.current[:iteration] = 0
              Thread.current[:started_at] = Time.current
              loop do
                if @should_cancel && !Thread.current[:canceled]
                  if channel.is_a?(Net::SSH::Connection::Channel)
                    if channel[:pty]
                      channel.send_data("\C-c") rescue false
                    elsif channel[:pid]
                      @ctn.kill_remote_process(channel[:pid])
                    end
                  end
                  channel.try(:close) rescue false
                  Process.kill(:SIGINT, channel[:ipc_thread].pid) if channel[:ipc_thread]
                  Thread.current[:canceled] = true
                end
                stat = status.gsub(":seconds", human_seconds(Time.current - Thread.current[:started_at]))
                #stat = stat.gsub(":workers", channel[:workers].to_s.presence || "?") if is_thread
                if channel[:error_message]
                  @status = ["[ERROR] #{channel[:error_message]}", :red]
                elsif channel.respond_to?(:active?) && !channel.active?
                  @status = ["[CLOSED] #{stat}", :red]
                elsif channel.closing?
                  @status = ["[CLOSING] #{stat}", :red]
                else
                  @status = [stat, color]
                end
                break unless channel.active?
                sleep 0.1
                Thread.current[:iteration] += 1
              end
            end
          end
        end
      end
    end
  end
end
