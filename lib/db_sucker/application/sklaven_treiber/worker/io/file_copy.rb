module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileCopy < Base
            attr_accessor :label

            def init
              @label ||= "copying"
              @entity ||= "copy"
            end

            def copy! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)
              prepare_local_destination

              try = 1
              begin
                reset_state
                @in_file  = File.new(@remote, "rb")
                @out_file = File.new(@local, "wb")
                @filesize = @in_file.size

                buf = ""
                @state = :copying
                begin
                  while @in_file.sysread(opts[:read_size], buf)
                    if !@closing && @abort_if.call(self)
                      @closing = true
                      break
                    end

                    @offset += buf.bytesize
                    @out_file.syswrite(buf)
                  end
                rescue EOFError
                end

                @in_file.close
                @out_file.close
                @state = :done
              rescue StandardError => ex
                @operror = "##{try} #{ex.class}: #{ex.message}"
                try += 1
                sleep 3
                if try > opts[:tries]
                  raise ex
                else
                  retry
                end
              end
            end
          end
        end
      end
    end
  end
end
