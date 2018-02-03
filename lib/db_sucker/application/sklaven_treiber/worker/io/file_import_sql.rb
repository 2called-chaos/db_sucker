module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class FileImportSql < Base
            MissingInstructionError = Class.new(::ArgumentError)
            InvalidInstructionError = Class.new(::ArgumentError)
            ImportError = Class.new(::RuntimeError)
            attr_accessor :instruction

            def init
              @label = "importing table"
              @entity = "table"
              @instruction = false
              @throughput.categories << :io << :io_import
            end

            def import! opts = {}
              raise MissingInstructionError, "no instruction given for import" unless @instruction.is_a?(Hash)
              raise InvalidInstructionError, "import instruction must at least contain :bin and :file keys" if [:bin, :file].any?{|w| !@instruction.key?(w) }
              opts = opts.reverse_merge(tries: 1, read_size: @read_size)

              execute(opts.slice(:tries).merge(sleep_error: 3)) do
                @in_file  = File.new(@instruction[:file], "rb")
                @filesize = @in_file.size if @filesize.zero?

                buf = ""
                @state = :working

                begin
                  debug "Opening process `#{@instruction[:bin]}'"
                  Open3.popen2e(@instruction[:bin], pgroup: true) do |_stdin, _stdouterr, _thread|
                    begin
                      # file prepend
                      _stdin.puts @instruction[:file_prepend] if @instruction[:file_prepend]

                      # file contents
                      begin
                        while @in_file.sysread(opts[:read_size], buf)
                          if !@closing && @abort_if.call(self)
                            @closing = true
                            break
                          end

                          @offset += buf.bytesize
                          _stdin.write(buf)
                          GC.start if @offset % GC_FORCE_RATE == 0
                        end
                      rescue EOFError
                      ensure
                        @in_file.close
                      end

                      # file append
                      _stdin.puts @instruction[:file_append] if @instruction[:file_append]
                    rescue Errno::EPIPE => ex
                      raise ImportError, "#{ex.message} (#{_stdouterr.read.chomp})"
                    end

                    # close & exit status
                    _stdin.close_write
                    exit_status = _thread.value
                    if exit_status == 0
                      debug "Process exited (#{exit_status}) `#{@instruction[:bin]}'"
                    else
                      warning "Process exited (#{exit_status}) `#{@instruction[:bin]}'"
                    end
                  end
                ensure
                  @state = :finishing
                end
              end
            end
          end
        end
      end
    end
  end
end
