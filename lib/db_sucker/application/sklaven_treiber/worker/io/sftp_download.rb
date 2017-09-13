module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class SftpDownload < Base
            UnknownEventError = Class.new(::RuntimeError)
            attr_reader :downloader

            def init
              @label = "downloading"
              @entity = "download"
            end

            def reset_state
              super
              @downloader = nil
            end

            def download! opts = {}
              opts = opts.reverse_merge(tries: 3, read_size: @read_size, force_new_connection: true)
              prepare_local_destination

              try = 1
              begin
                reset_state
                @ctn.sftp_start(opts[:force_new_connection]) do |sftp|
                  @filesize = sftp.lstat!(@remote).size
                  sftp.download!(@remote, @local, read_size: opts[:read_size]) do |event, downloader, *args|
                    if !@closing && @abort_if.call(self, event, downloader, *args)
                      downloader.abort!
                      @closing = true
                    end

                    case event
                    when :open
                      @downloader = downloader
                      @state = :init
                    when :get
                      @state = :downloading
                      @offset = args[1] + args[2].length
                    when :close
                      @state = :finishing
                    when :finish
                      @state = :done
                    else
                      raise UnknownEventError, "unknown event `#{event}'"
                    end
                  end
                end
                @on_success.call(self) if !@closing && !@worker.should_cancel
              rescue Net::SSH::Disconnect => ex
                @operror = "##{try} #{ex.class}: #{ex.message}"
                @on_error.call(self, ex, @operror)
                try += 1
                sleep 3
                if try > opts[:tries]
                  raise ex
                else
                  retry
                end
              ensure
                @on_complete.call(self)
              end
            end
          end
        end
      end
    end
  end
end
