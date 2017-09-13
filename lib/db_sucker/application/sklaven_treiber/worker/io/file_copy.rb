module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileCopy < Base
            attr_accessor :use_tmp

            def init
              @label = "copying"
              @entity = "copy"
              @use_tmp = true
            end

            def copy! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)
              prepare_local_destination

              try = 1
              begin
                reset_state
                @tmploc   = @use_tmp ? "#{@local}.tmp" : @local
                @in_file  = File.new(@remote, "rb")
                @out_file = File.new(@tmploc, "wb")
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
                ensure
                  @state = :finishing
                  @in_file.close
                  @out_file.close
                end

                FileUtils.mv(@tmploc, @local) if @use_tmp

                @state = :verifying
                src_hash = @integrity.call(@remote)
                dst_hash = @integrity.call(@local)
                if src_hash != dst_hash
                  raise DataIntegrityError, "Integrity check failed! [SRC](#{src_hash}) != [DST](#{dst_hash})"
                end

                @state = :done
                @on_success.call(self) if !@closing && !@worker.should_cancel
              rescue StandardError => ex
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
