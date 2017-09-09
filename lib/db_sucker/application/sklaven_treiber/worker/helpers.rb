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
            IO::SftpDownload.new(*args).tap do |dl|
              block.try(:call, dl)
            end
          end

          def file_copy *args, &block
            IO::FileCopy.new(*args).tap do |fc|
              block.try(:call, fc)
            end
          end

          def second_progress channel, status, color = :yellow, is_thread = false, initial = 0
            Thread.new do
              Thread.current[:iteration] = initial
              loop do
                stat = status.gsub(":seconds", human_seconds(Thread.current[:iteration]))
                if @should_cancel && !Thread.current[:canceled]
                  channel.send_data("\C-c") rescue false if channel.is_a?(Net::SSH::Connection::Channel)
                  channel.close rescue false
                  Thread.current[:canceled] = true
                end
                stat = stat.gsub(":workers", channel[:workers].to_s.presence || "?") if is_thread
                if channel[:error_message]
                  @status = ["[IMPORT] #{channel[:error_message]}", :red]
                elsif channel.respond_to?(:active?) && !channel.active?
                  @status = ["[CLOSED] #{stat}", :red]
                elsif channel.closing?
                  @status = ["[CLOSING] #{stat}", :red]
                else
                  @status = [stat, color]
                end
                break unless channel.active?
                sleep 1
                Thread.current[:iteration] += 1
              end
            end
          end
        end
      end
    end
  end
end
