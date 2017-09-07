module DbSucker
  class Application
    class Window
      include Curses
      COLOR_GRAY = 8
      COL1 = 20
      COL2 = 25
      COL3 = 20
      attr_reader :app, :sklaventreiber
      attr_accessor :view
      OutputHelper.hook(self)

      def initialize app, sklaventreiber
        @app = app
        @sklaventreiber = sklaventreiber
        @monitor = Monitor.new
        @l = 0
        @t = 0
        @view = :status
      end

      def start_loop refresh_delay
        @loop = Thread.new do
          Thread.current.abort_on_exception = true
          loop do
            break if Thread.current[:stop]
            refresh_screen if app.opts[:window_draw]
            sleep refresh_delay
          end
        end
      end

      def stop_loop
        return unless @loop
        @loop[:stop] = true
        @loop.join
      end

      def line l = 1
        setpos(l - 1, 0)
      end

      def next_line
        @l += 1
        setpos(@l, 0)
      end

      def update
        clear
        @l = -1
        yield if block_given?
        next_line
        refresh
      end

      def refresh_screen
        @monitor.synchronize do
          @t += 1
          update { __send__(:"_render_#{@view}") }
        end
      rescue StandardError => ex
        update do
          next_line
          attron(color_pair(COLOR_RED)|A_NORMAL) { addstr("RenderError occured!") }
          next_line
          attron(color_pair(COLOR_RED)|A_NORMAL) { addstr("#{ex.class}: #{ex.message}") }
          ex.backtrace.each do |l|
            next_line
            attron(color_pair(COLOR_RED)|A_NORMAL) { addstr("    #{l}") }
          end
        end
        sleep 1
      end

      def change_view new_view
        if block_given?
          view_was = @view
          begin
            @view = new_view
            yield
          ensure
            @view = view_was
          end
        else
          @view = new_view
        end
      end

      def init!
        app.debug "Entering curses screen mode"
        init_screen
        nl
        # noecho
        # cbreak
        # raw
        # stdscr.keypad = true

        # colors
        start_color
        use_default_colors
        [COLOR_BLACK, COLOR_RED, COLOR_GREEN, COLOR_YELLOW, COLOR_BLUE, COLOR_MAGENTA, COLOR_CYAN, COLOR_WHITE].each do |cl|
          init_pair(cl, cl, -1)
        end
        init_pair(COLOR_GRAY, 0, -1)
      end

      def close
        stop_loop
        close_screen
        app.debug "Leaving curses screen mode"
      end

      # def progress_bar label, is, max, maxlength = nil
      #   cr = maxlength || (cols-1)
      #   cr -= label.length + 1

      #   lp = is.to_f / max * 100
      #   lps = " #{app.human_number(is)}/#{app.human_number(max)} – #{app.human_percentage(lp, 0)}"
      #   cr -= lps.length + 1 if cr > lps.length

      #   lc = lp > 90 ? COLOR_RED : lp > 75 ? COLOR_YELLOW : COLOR_GREEN
      #   crr = (cr.to_f * (lp / 100)).ceil.to_i

      #   attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("#{label} ") }
      #   attron(color_pair(lc)|A_NORMAL) { addstr("[") }
      #   attron(color_pair(lc)|A_NORMAL) { addstr("".ljust(crr, "|")) }
      #   attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr("".ljust(cr - crr, "-")) }
      #   attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr(lps) }
      #   attron(color_pair(lc)|A_NORMAL) { addstr("]") }
      # end

      def _render_status
        next_line
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("        Status: ") }
        attron(color_pair(self.class.const_get "COLOR_#{sklaventreiber.status[1].to_s.upcase.presence || "BLUE"}")|A_NORMAL) { addstr(sklaventreiber.status[0]) }
        # shutdown message
        if $core_runtime_exiting && sklaventreiber.status[0] != "terminated"
          attron(color_pair(COLOR_RED)|A_BOLD) { addstr(" (HALTING … please wait)") }
        end

        next_line
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("       Threads: ") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{Thread.list.length} ".ljust(COL1, " ")) }

        # attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("Connections: ") }
        # attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{Thread.list.length} ".ljust(COL1, " ")) }

        next_line
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("       Started: ") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{@app.boot}") }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(" (") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr(human_seconds(Time.current - app.boot)) }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(")") }

        next_line
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("Transaction ID: ") }
        attron(color_pair(COLOR_CYAN)|A_NORMAL) { addstr(sklaventreiber.trxid) }

        next_line
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("      Database: ") }
        attron(color_pair(COLOR_MAGENTA)|A_NORMAL) { addstr(sklaventreiber.data[:database] || "?") }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(" (transfering ") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{sklaventreiber.data[:tables_transfer] || "?"}") }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(" of ") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{sklaventreiber.data[:tables_total] || "?"}") }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(" tables)") }

        next_line
        total, done = sklaventreiber.data[:tables_transfer], sklaventreiber.data[:tables_done]
        perc = total && done ? human_percentage(total.zero? ? 100 : done / total.to_f * 100) : "?"
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("      Progress: ") }
        attron(color_pair(COLOR_GREEN)|A_NORMAL) { addstr(perc) }
        attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr(" – ") }
        attron(color_pair(COLOR_BLUE)|A_NORMAL) { addstr("#{done}/#{total || "?"} workers done") }

        if sklaventreiber.workers.any?
          next_line
          limit = lines - @l - 3 # @l starting at 0, 1 for blank line to come, placeholder
          enum = sklaventreiber.workers.sort_by{|w| [w.priority, w.table] }
          enum.each_with_index do |w, i|
            # limit reached and more than one entry to come?
            if i > limit && (enum.length - i - 1) > 0
              next_line
              rest = enum[i..-1]
              part = rest.group_by(&:state).map do |k, v|
                "#{v.length} #{k}"
              end
              attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("… #{rest.length} more [#{part.join(", ")}]") }
              break
            end
            _render_line(w)
          end
        end
      end

      def _render_line worker
        next_line
        col1 = sklaventreiber.data[:window_col1]
        col2 = sklaventreiber.data[:window_col2]

        # status icon
        case worker.state
          when :pending then attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr("⊙") }
          when :aquired then attron(color_pair(COLOR_WHITE)|A_NORMAL) { addstr("⊙") }
          when :done then attron(color_pair(COLOR_GREEN)|A_NORMAL) { addstr("✔") }
          when :failed then attron(color_pair(COLOR_RED)|A_NORMAL) { addstr("✘") }
          when :canceled then attron(color_pair(COLOR_RED)|A_NORMAL) { addstr("⊘") }
          when :running then
            c = case @t % 4
              when 0 then "◜" # "╭"
              when 1 then "◝" # "╮"
              when 2 then "◞" # "╯"
              when 3 then "◟" # "╰"
            end
            attron(color_pair(COLOR_YELLOW)|A_NORMAL) { addstr("#{c}") }
        end

        # table_name
        attron(color_pair(COLOR_MAGENTA)|A_NORMAL) { addstr(" #{worker.table}".ljust(col1 + 2, " ")) }
        attron(color_pair(COLOR_GRAY)|A_NORMAL) { addstr(" | ") }

        # status
        if worker.step
          attron(color_pair(COLOR_CYAN)|A_NORMAL) { addstr("[#{worker.step}/#{worker.perform.length}] ") }
        end
        attron(color_pair(self.class.const_get "COLOR_#{worker.status[1].to_s.upcase.presence || "BLUE"}")|A_NORMAL) { addstr(worker.status[0]) }
      end
    end
  end
end