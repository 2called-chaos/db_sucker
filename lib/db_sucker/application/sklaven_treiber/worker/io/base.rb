module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class Base
            UnknownFormatterError = Class.new(::ArgumentError)
            DataIntegrityError = Class.new(::RuntimeError)
            STATUS_FORMATTERS = [:none, :minimal, :full]
            attr_reader :status_format, :state, :operror, :offset, :closing, :local, :remote, :ctn
            attr_accessor :read_size, :label, :entity, :filesize, :throughput
            OutputHelper.hook(self)

            def initialize worker, ctn, fd
              # references
              @worker = worker
              @ctn = ctn

              # remote & local
              @remote = fd.is_a?(Hash) ? fd.keys[0] : fd
              @local = fd.values[0] if fd.is_a?(Hash)

              # defaults
              @label ||= "working"
              @entity ||= "task"
              @status_format = :off
              @throughput = worker.sklaventreiber.throughput.register(self)
              @read_size = 128 * 1024 # 128kb
              @filesize = 0

              # callbacks
              @integrity = Proc.new {}
              @abort_if = Proc.new { false }
              @on_error = Proc.new {}
              @on_complete = Proc.new {}
              @on_success = Proc.new {}
              init
              reset_state
            end

            def init
            end

            def reset_state
              @operror = nil
              @closing = false
              @state = :idle
              @offset = 0
              @throughput.reset_stats
            end

            def integrity &block
              @integrity = block
            end

            def abort_if &block
              @abort_if = block
            end

            def on_error &block
              @on_error = block
            end

            def on_complete &block
              @on_complete = block
            end

            def on_success &block
              @on_success = block
            end

            def status_format= which
              which = which.to_sym
              raise UnknownFormatterError, "unknown status format `#{which}', available options: #{STATUS_FORMATTERS * ", "}" unless STATUS_FORMATTERS.include?(which)
              @status_format = which
            end

            def prepare_local_destination
              FileUtils.mkdir_p(File.dirname(@local))
            end

            def execute opts = {}, &block
              opts = opts.reverse_merge(tries: 1, sleep_error: 0)
              try = 1
              begin
                reset_state
                throughput.measure(&block)
                if !@closing && !@worker.should_cancel
                  @state = :done
                  @on_success.call(self)
                end
              rescue StandardError => ex
                @operror = "##{try} #{ex.class}: #{ex.message}"
                @on_error.call(self, ex, @operror)
                try += 1
                if try > opts[:tries]
                  raise ex
                else
                  sleep opts[:sleep_error]
                  retry
                end
              ensure
                @on_complete.call(self)
              end
            ensure
              @throughput.unregister
            end

            def to_s
              return @operror if @operror
              tp = @throughput

              [].tap do |r|
                r << "[CLOSING]" if @closing
                if @status_format == :none
                  r << "#{@label}"
                  break
                end
                case @state
                when :idle, :init
                  r << "#{@label}:"
                  r << " initiating..."
                when :finishing
                  r << "#{@label}:"
                  r << " finishing..."
                when :verifying
                  r << "#{@label}:"
                  r << " verifying..."
                when :done
                  r << "#{@entity || @label} #{@offset == @filesize ? "complete" : "INCOMPLETE"}: #{tp.f_done_percentage} – #{tp.f_byte_progress}"
                when :downloading, :copying, :decompressing, :working
                  r << "#{@label}:"
                  r << tp.f_done_percentage.rjust(7, " ")
                  if @status_format == :minimal
                    r << "[#{tp.f_eta}]"
                  elsif @status_format == :full
                    r << "[#{tp.f_eta} – #{tp.f_bps.rjust(9, " ")}/s]"
                  end

                  if @status_format == :full
                    f_has, f_tot = tp.f_offset, tp.f_filesize
                    r << "[#{f_has.rjust(f_tot.length, "0")}/#{f_tot}]"
                  end
                end
              end * " "
            end

            def to_curses target
              _this = self
              tp = @throughput
              target.instance_eval do
                if _this.operror
                  red "#{_this.operror}"
                  return
                end

                if _this.closing
                  red "[CLOSING] "
                end

                if _this.status_format == :none
                  blue "#{_this.label}"
                  break
                end

                case _this.state
                when :idle, :init
                  yellow "#{_this.label}: "
                  gray " initiating..."
                when :finishing
                  yellow "#{_this.label}: "
                  gray " finishing..."
                when :verifying
                  yellow "#{_this.label}: "
                  gray " verifying..."
                when :done
                  if _this.offset == _this.filesize
                    green "#{_this.entity || _this.label} complete: #{tp.f_done_percentage}"
                    yellow " – "
                    cyan "#{human_bytes _this.offset}"
                  else
                    red "#{_this.entity || _this.label} INCOMPLETE: #{tp.f_done_percentage}"
                    yellow " – "
                    cyan "#{tp.f_byte_progress}"
                  end
                when :downloading, :copying, :decompressing, :working
                  yellow "#{_this.label}: "
                  diffp = tp.done_percentage
                  color = diffp > 90 ? :green : diffp > 75 ? :blue : diffp > 50 ? :cyan : diffp > 25 ? :yellow : :red
                  send(color, tp.f_done_percentage.rjust(7, " ") << " ")

                  if _this.status_format == :minimal
                    yellow "[#{tp.f_eta}]"
                  elsif _this.status_format == :full
                    yellow "[#{tp.f_eta} – #{tp.f_bps.rjust(9, " ")}/s]"
                  end

                  if _this.status_format == :full
                    f_has, f_tot = tp.f_offset, tp.f_filesize
                    gray " [#{f_has.rjust(f_tot.length, "0")}/#{f_tot}]"
                  end

                  progress_bar(diffp, prog_done_color: color, prog_current_color: color)
                end
              end
            end
          end
        end
      end
    end
  end
end
