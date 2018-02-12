module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileGunzip < Base
            attr_accessor :use_tmp
            attr_accessor :preserve_original

            def init
              @label = "decompressing"
              @entity = "decompress"
              @use_tmp = true
              @preserve_original = false
              @local ||= "#{File.dirname(@remote)}/#{File.basename(@remote, ".gz")}"
              @throughput.categories << :io << :io_gunzip
            end

            def gunzip! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)
              prepare_local_destination

              execute(opts.slice(:tries).merge(sleep_error: 3)) do
                @tmploc   = @use_tmp ? "#{@local}.tmp" : @local
                @in_file  = File.new(@remote, "rb")
                @out_file = File.new(@tmploc, "wb")
                @filesize = @in_file.size if @filesize.zero?

                @state = :decompressing
                gz = Zlib::GzipReader.new(@in_file)
                begin
                  while buf = gz.read(opts[:read_size])
                    if !@closing && @abort_if.call(self)
                      @closing = true
                      break
                    end

                    @offset += [opts[:read_size], @filesize - @offset].min
                    @out_file.syswrite(buf)
                    GC.start if @offset % GC_FORCE_RATE == 0
                  end
                ensure
                  @state = :finishing
                  gz.close
                  @out_file.close
                end

                FileUtils.mv(@tmploc, @local) if @use_tmp
                File.unlink(@remote) unless @preserve_original
              end
            end
          end
        end
      end
    end
  end
end
