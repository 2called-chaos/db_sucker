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
              @throughput.categories << :io << :io_file_copy
            end

            def copy! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)
              prepare_local_destination

              execute(opts.slice(:tries).merge(sleep_error: 3)) do
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
                    GC.start if @offset % GC_FORCE_RATE == 0
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
              end
            end
          end
        end
      end
    end
  end
end
