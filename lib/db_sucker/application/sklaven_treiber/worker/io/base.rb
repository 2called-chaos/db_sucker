module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class Base
            UnknownFormatterError = Class.new(::ArgumentError)
            DataIntegrityError = Class.new(::RuntimeError)
            STATUS_FORMATTERS = [:none, :minimal, :full]
            attr_reader :status_format, :state, :operror, :filesize, :offset, :closing, :local, :remote, :ctn
            attr_accessor :read_size, :last_offset, :last_time, :label, :entity
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
              @last_offset = 0
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

            def to_s
              return @operror if @operror

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
                  r << "#{@entity || @label} #{@offset == @filesize ? "complete" : "INCOMPLETE"}: #{f_percentage(@offset, @filesize)} – #{human_bytes @offset}/#{human_bytes @filesize}"
                when :downloading, :copying, :decompressing, :working
                  bytes_remain = @filesize - @offset
                  if @last_time
                    offset_diff = @offset - @last_offset
                    time_diff = (Time.current - @last_time).to_d
                    bps = (time_diff * offset_diff.to_d) * (1.to_d/time_diff)
                  else
                    offset_diff = 0
                    bps = 0
                  end
                  eta = bps.zero? ? "?:¿?:¿?" : human_seconds2(bytes_remain / bps)

                  r << "#{@label}:"
                  r << f_percentage(@offset, @filesize).rjust(7, " ")
                  if @status_format == :minimal
                    r << "[#{eta}]"
                  elsif @status_format == :full
                    r << "[#{eta} – #{human_bytes(bps).rjust(9, " ")}/s]"
                  end

                  if @status_format == :full
                    f_has = human_bytes @offset
                    f_tot = human_bytes @filesize
                    r << "[#{f_has.rjust(f_tot.length, "0")}/#{f_tot}]"
                  end


                  @last_offset = @offset
                  @last_time = Time.current
                end
              end * " "
            end

            def to_curses target
              _this = self
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
                  fperc = f_percentage(_this.offset, _this.filesize)
                  if _this.offset == _this.filesize
                    green "#{_this.entity || _this.label} complete: #{fperc}"
                    yellow " – "
                    cyan "#{human_bytes _this.offset}"
                  else
                    red "#{_this.entity || _this.label} INCOMPLETE: #{fperc}"
                    yellow " – "
                    cyan "#{human_bytes _this.offset}/#{human_bytes _this.filesize}"
                  end
                when :downloading, :copying, :decompressing, :working
                  bytes_remain = _this.filesize - _this.offset
                  if _this.last_time
                    offset_diff = _this.offset - _this.last_offset
                    time_diff = (Time.current - _this.last_time).to_d
                    bps = (time_diff * offset_diff.to_d) * (1.to_d/time_diff)
                  else
                    offset_diff = 0
                    bps = 0
                  end
                  eta = bps.zero? ? "?:¿?:¿?" : human_seconds2(bytes_remain / bps)

                  yellow "#{_this.label}: "
                  diffp = _this.offset == 0 ? 0 : _this.offset.to_d / _this.filesize.to_d * 100.to_d
                  color = diffp > 90 ? :green : diffp > 75 ? :blue : diffp > 50 ? :cyan : diffp > 25 ? :yellow : :red
                  send(color, f_percentage(_this.offset, _this.filesize).rjust(7, " ") << " ")

                  if _this.status_format == :minimal
                    yellow "[#{eta}]"
                  elsif _this.status_format == :full
                    yellow "[#{eta} – #{human_bytes(bps).rjust(9, " ")}/s]"
                  end

                  if _this.status_format == :full
                    f_has = human_bytes _this.offset
                    f_tot = human_bytes _this.filesize
                    gray " [#{f_has.rjust(f_tot.length, "0")}/#{f_tot}]"
                  end

                  # progress bar
                  max = cols - stdscr.curx - 3
                  pnow = (max.to_d * (diffp / 100.to_d)).ceil.to_i
                  yellow " ["
                  send(color, "".ljust(pnow, "#"))
                  gray "".ljust(max - pnow, ".")
                  yellow "]"

                  _this.last_offset = _this.offset
                  _this.last_time = Time.current
                end
              end
            end
          end
        end
      end
    end
  end
end
