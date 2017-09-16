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
              @throughput.categories << :inet << :inet_down
            end

            def reset_state
              super
              @downloader = nil
            end

            def download! opts = {}
              opts = opts.reverse_merge(tries: 3, read_size: @read_size, force_new_connection: true)
              prepare_local_destination
              execute(opts.slice(:tries).merge(sleep_error: 3)) do
                @ctn.sftp_start(opts[:force_new_connection]) do |sftp|
                  @filesize = sftp.lstat!(@remote).size
                  sftp.download!(@remote, @local, read_size: opts[:read_size], requests: 1) do |event, downloader, *args|
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
                      GC.start if @offset % GC_FORCE_RATE == 0
                    when :close
                      @state = :finishing
                    when :finish
                      @state = :done
                    else
                      raise UnknownEventError, "unknown event `#{event}'"
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
