module DbSucker
  class Application
    class Window
      module Core
        UnknownSpinnerError = Class.new(::RuntimeError)
        SPINNERS = {
          arrows: "←↖↑↗→↘↓↙",
          blocks: "▁▃▄▅▆▇█▇▆▅▄▃",
          blocks2: "▉▊▋▌▍▎▏▎▍▌▋▊▉",
          blocks3: "▖▘▝▗",
          blocks4: "▌▀▐▄",
          forks: "┤┘┴└├┌┬┐",
          triangles: "◢◣◤◥",
          trbl_square: "◰◳◲◱",
          trbl_circle: "◴◷◶◵",
          circle_half: "◐◓◑◒",
          circle_quarter: "◜◝◞◟",
          circle_quarter2: "╮╯╰╭",
          unix: "|/-\\",
          bomb: ".oO@*",
          eye: "◡⊙◠",
          diamond: "◇◈◆",
        }

        def start
          @keypad.start_loop
          start_window_loop
        end

        def stop
          stop_window_loop
          @keypad.stop_loop
          close_screen
          app.debug "Leaving curses screen mode"
        end

        def start_window_loop
          @loop = app.spawn_thread(:window_draw_loop) do |thr|
            loop do
              break if thr[:stop] && (@view == :status || @force_kill)
              refresh_screen if app.opts[:window_draw]
              thr.wait(app.opts[:window_refresh_delay])
            end
          end
        end

        def stop_window_loop
          return unless @loop
          @loop[:stop] = true
          @loop.signal.join
        end

        def choose_spinner
          spinner = app.opts[:window_spinner]
          spinner = SPINNERS.keys.sample if spinner == :random
          if s = SPINNERS[spinner]
            @spinner_frames = s.split("").reverse.freeze
          else
            raise UnknownSpinnerError, "The spinner `#{spinner}' does not exist, use :random or one of: #{SPINNERS.keys * ", "}"
          end
        end

        def init!
          app.debug "Entering curses screen mode"
          init_screen
          nl
          if @app.opts[:window_keypad]
            raw
            nonl
            noecho
            cbreak
            stdscr.keypad = true
            set_cursor 0
          end

          # colors
          start_color
          use_default_colors
          [:COLOR_BLACK, :COLOR_RED, :COLOR_GREEN, :COLOR_YELLOW, :COLOR_BLUE, :COLOR_MAGENTA, :COLOR_CYAN, :COLOR_WHITE].each do |cl|
            c = Window.const_get(cl)
            init_pair(c, c, -1)
          end
          init_pair(Window::COLOR_GRAY, 0, -1)
        end

        def flashbang
          flash
        end

        def set_cursor visibility
          curs_set(visibility)
        end

        def force_cursor line, col = 0
          if line.nil?
            @force_cursor = nil
          else
            @force_cursor = [line, col]
          end
        end

        def update
          clear
          @x_offset = 0
          @line = -1
          yield if block_given?
          next_line
          setpos(*@force_cursor) if @force_cursor
          refresh
        end

        def line l = 1
          setpos(l - 1, @x_offset)
        end

        def next_line
          @line += 1
          setpos(@line, @x_offset)
        end

        def change_view new_view
          view_was = @view
          if block_given?
            begin
              @view = new_view
              yield
            ensure
              @view = view_was
            end
          else
            @view = new_view
            view_was
          end
        end

        def progress_bar perc, opts = {}
          opts = opts.reverse_merge({
            width: cols - stdscr.curx - 3,
            prog_open: "[",
            prog_open_color: "yellow",
            prog_done: "=",
            prog_done_color: "green",
            prog_current: ">",
            prog_current_color: "yellow",
            prog_remain: ".",
            prog_remain_color: "gray",
            prog_close: "]",
            prog_close_color: "yellow",
          })
          pdone = (opts[:width].to_d * (perc.to_d / 100.to_d)).ceil.to_i
          prem  = opts[:width] - pdone
          pcur  = 0
          if perc < 100
            pdone.zero? ? (prem -= 1) : (pdone -= 1)
            pcur  += 1
          end

          send(opts[:prog_open_color], " #{opts[:prog_open]}")
          send(opts[:prog_done_color], "".ljust(pdone, opts[:prog_done])) unless pdone.zero?
          send(opts[:prog_current_color], "".ljust(pcur, opts[:prog_current])) unless pcur.zero?
          send(opts[:prog_remain_color], "".ljust(prem, opts[:prog_remain])) unless prem.zero?
          send(opts[:prog_close_color], "#{opts[:prog_close]}")
        end

        def dialog &block
          Dialog.new(self, &block)
        end

        def dialog! &block
          dialog(&block).render!
        end

        # colors
        [:red, :blue, :yellow, :cyan, :magenta, :gray, :green, :white].each do |c|
          define_method(c) do |*args, &block|
            color = Window.const_get "COLOR_#{c.to_s.upcase}"
            attron(color_pair(color)|Window::A_NORMAL) do
              if block
                block.call
              else
                args.each {|a| addstr(a) }
              end
            end
          end
        end
      end
    end
  end
end
