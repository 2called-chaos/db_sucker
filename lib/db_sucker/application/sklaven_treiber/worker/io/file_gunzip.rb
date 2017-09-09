module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileGunzip < Base
            attr_accessor :use_tmp
            attr_accessor :preserve_original

            def init
              @label ||= "decompressing"
              @entity ||= "decompress"
              @use_tmp = true
              @preserve_original = false
              @local ||= "#{File.dirname(@remote)}/#{File.basename(@remote, ".gz")}"
            end

            def gunzip! opts = {}
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)
              prepare_local_destination

              try = 1
              begin
                reset_state
                @tmploc   = @use_tmp ? "#{@local}.tmp" : @local
                @in_file  = File.new(@remote, "rb")
                @out_file = File.new(@tmploc, "wb")
                @filesize = @in_file.size

                @state = :decompressing
                gz = Zlib::GzipReader.new(@in_file)
                begin
                  while buf = gz.read(opts[:read_size])
                    @offset += buf.bytesize
                    @out_file.syswrite(buf)
                  end
                ensure
                  gz.close
                end

                @in_file.close
                @out_file.close
                FileUtils.mv(@tmploc, @local) if @use_tmp
                File.unlink(@remote) unless @preserve_original

                @state = :done
                @on_success.call(self)
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
