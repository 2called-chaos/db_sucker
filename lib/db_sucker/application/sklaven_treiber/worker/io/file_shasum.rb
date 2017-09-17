module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class Shasum < Base
            attr_accessor :sha, :result

            def init
              @label = "verifying"
              @entity = "verification"
              @sha ||= 1
              @throughput.categories.clear # IO read
            end

            def verify! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)

              execute(opts.slice(:tries).merge(sleep_error: 3)) do
                @in_file  = File.new(@remote, "rb")
                @filesize = @in_file.size

                @state = :working
                sha = "Digest::SHA#{@sha}".constantize.new
                buf = ""
                begin
                  while @in_file.read(opts[:read_size], buf)
                    if !@closing && @abort_if.call(self)
                      @closing = true
                      break
                    end

                    @offset += buf.bytesize
                    sha << buf
                    GC.start if @offset % GC_FORCE_RATE == 0
                  end
                ensure
                  @state = :finishing
                  @in_file.close
                  @result = sha.hexdigest
                end
              end
            end
          end
        end
      end
    end
  end
end
