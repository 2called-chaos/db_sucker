module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileCopy < Base
            attr_accessor :use_tmp, :integrity

            def init
              @label = "copying"
              @entity = "copy"
              @use_tmp = true
              @integrity = true
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
                src_hash = verify_file(@remote, 0)
                dst_hash = verify_file(@local, 1)
                if src_hash != dst_hash
                  raise DataIntegrityError, "Integrity check failed! [SRC](#{src_hash}) != [DST](#{dst_hash})"
                end
              end
            end

            def verify_file file, index = 0
              result = false
              @worker.file_shasum(@ctn, file) do |fc|
                fc.sha = @ctn.integrity_sha
                fc.status_format = :none
                fc.throughput.sopts[:perc_modifier] = 0.5
                fc.throughput.sopts[:perc_base] = index * 50
                @verify_handle = fc

                fc.abort_if { @should_cancel }
                fc.on_success do
                  result = fc.result
                end
                fc.verify!
              end
              @verify_handle = false
              return result
            end
          end
        end
      end
    end
  end
end
