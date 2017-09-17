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
          @loop = Thread.new do
            Thread.current[:itype] = :window_draw_loop
            Thread.current.priority = @app.opts[:tp_window_draw_loop]
            loop do
              break if Thread.current[:stop]
              refresh_screen if app.opts[:window_draw]
              sleep app.opts[:window_refresh_delay]
            end
          end
        end

        def stop_window_loop
          return unless @loop
          @loop[:stop] = true
          @loop.join
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
            curs_set 0
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

        def update
          clear
          @line = -1
          yield if block_given?
          next_line
          refresh
        end

        def line l = 1
          setpos(l - 1, 0)
        end

        def next_line
          @line += 1
          setpos(@line, 0)
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
