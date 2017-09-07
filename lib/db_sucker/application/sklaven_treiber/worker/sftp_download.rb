module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        class SftpDownload
          STATUS_FORMATTERS = [:none, :minimal, :full]
          attr_reader :status_format, :state, :downloader, :error, :filesize, :offset
          attr_accessor :read_size
          OutputHelper.hook(self)

          def initialize ctn, fd
            @ctn = ctn
            @remote = fd.keys[0]
            @local = fd.values[0]
            @status_format = :off
            @read_size = 5 * 1024 * 1024
            reset_state
          end

          def reset_state
            @error = nil
            @closing = false
            @downloader = nil
            @state = :idle
            @offset = 0
            @last_offset = 0
          end

          def status_format= which
            which = which.to_sym
            raise "unknown status format `#{which}', available options: #{STATUS_FORMATTERS * ", "}" unless STATUS_FORMATTERS.include?(which)
            @status_format = which
          end

          def prepare_local_destination
            FileUtils.mkdir_p(File.dirname(@local))
          end

          def download! opts = {}
            opts = opts.reverse_merge(tries: 1, read_size: @read_size, force_new_connection: true)
            prepare_local_destination

            try = 1
            begin
              reset_state
              @ctn.sftp_start(opts[:force_new_connection]) do |sftp|
                @filesize = sftp.lstat!(@remote).size
                sftp.download!(@remote, @local, read_size: opts[:read_size]) do |event, downloader, *args|
                  if $core_runtime_exiting && !@closing
                    downloader.abort!
                    @closing = true
                  end

                  case event
                  when :open
                    @downloader = downloader
                    @state = :init
                  when :get
                    @state = :downloading
                    @offset = args[1] + args[2].length
                  when :close
                    @state = :finishing
                  when :finish
                    @state = :done
                  else
                    raise("unknown event #{event}")
                  end
                end
              end
            rescue Net::SSH::Disconnect => ex
              @error = "##{try} #{ex.class}: #{ex.message}"
              try += 1
              sleep 3
              if try > opts[:tries]
                raise ex
              else
                retry
              end
            end
          end

          def to_s
            return @error if @error

            _str = [].tap do |r|
              r << "[CLOSING]" if @closing
              if @status_format == :none
                r << "downloading"
                break
              end
              case @state
              when :idle
                r << "downloading:"
                r << "initiating..."
              when :init
                r << "downloading:"
                r << "initiating..."
              when :finishing
                r << "downloading:"
                r << "finishing..."
              when :done
                r << "download complete: 100% – #{human_bytes @filesize}"
              when :downloading
                bytes_remain = @filesize - @offset
                if @last_time
                  offset_diff = @offset - @last_offset
                  time_diff = (Time.now - @last_time).to_d
                  bps = (time_diff * offset_diff.to_d) * (1.to_d/time_diff)
                  eta = human_seconds2(bytes_remain / bps)
                else
                  offset_diff = 0
                  bps = 0
                  eta = "???"
                end

                r << "downloading:"
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

                r << f_percentage(@offset, @filesize).rjust(7, " ")

                r << "[#########.............]"

                @last_offset = @offset
                @last_time = Time.now
              end
            end * " "
            c(_str, @closing ? :red : :yellow)
          end

          # def to_curses
          #   Proc.new do

          #   end

          #   # def progress_bar label, is, max, maxlength = nil
          #   #   cr = maxlength || (cols-1)
          #   #   cr -= label.length + 1

          #   #   lp = is.to_f / max * 100
          #   #   lps = " #{app.human_number(is)}/#{app.human_number(max)} – #{app.human_percentage(lp, 0)}"
          #   #   cr -= lps.length + 1 if cr > lps.length

          #   #   lc = lp > 90 ? COLOR_RED : lp > 75 ? COLOR_YELLOW : COLOR_GREEN
          #   #   crr = (cr.to_f * (lp / 100)).ceil.to_i

          #   #   attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("#{label} ") }
          #   #   attron(color_pair(lc)|A_NORMAL) { addstr("[") }
          #   #   attron(color_pair(lc)|A_NORMAL) { addstr("".ljust(crr, "|")) }
          #   #   attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr("".ljust(cr - crr, "-")) }
          #   #   attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr(lps) }
          #   #   attron(color_pair(lc)|A_NORMAL) { addstr("]") }
          #   # end
          # end
        end
      end
    end
  end
end

__END__
