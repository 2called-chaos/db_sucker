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
            SftpDownload.new(*args).tap do |dl|
              block.try(:call, dl)
            end
          end

          def second_progress channel, status, color = :yellow, is_thread = false, initial = 0
            Thread.new do
              Thread.current[:iteration] = initial
              loop do
                channel.close rescue false if $core_runtime_exiting
                stat = status.gsub(":seconds", human_seconds(Thread.current[:iteration]))
                stat = stat.gsub(":workers", channel[:workers].to_s.presence || "?") if is_thread
                if channel[:error_message]
                  @status = ["[IMPORT] #{channel[:error_message]}", :red]
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
