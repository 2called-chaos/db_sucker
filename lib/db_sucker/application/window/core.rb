module DbSucker
  class Application
    class Window
      module Core
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
