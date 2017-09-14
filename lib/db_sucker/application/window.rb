module DbSucker
  class Application
    class Window
      include Curses
      COLOR_GRAY = 8
      COL1 = 20
      COL2 = 25
      COL3 = 20
      OutputHelper.hook(self)

      attr_reader :app, :sklaventreiber
      attr_accessor :view

      def initialize app, sklaventreiber
        @app = app
        @sklaventreiber = sklaventreiber
        @monitor = Monitor.new
        @l = 0 # line
        @t = 0 # tick
        @view = :status
      end

      def start_loop refresh_delay
        @loop = Thread.new do
          Thread.current[:itype] = :window_draw_loop
          Thread.current.priority = @app.opts[:tp_window_draw_loop]
          loop do
            break if Thread.current[:stop]
            refresh_screen if app.opts[:window_draw]
            sleep refresh_delay
          end
        end
        @keyloop = Thread.new do
          Thread.current[:itype] = :window_keypad_loop
          Thread.current.priority = @app.opts[:tp_window_keypad_loop]
          Thread.current[:monitor] = Monitor.new
          loop do
            ch = getch
            Thread.current[:monitor].synchronize do
              case ch
              when "P" # kill SSH poll
                sklaventreiber.poll.try(:kill)
              when "T" # dump threads (development)
                dump_file = "#{app.core_tmp_path}/threaddump-#{Time.current.to_i}.log"
                File.open(dump_file, "wb") do |f|
                  f.puts "#{Thread.list.length} threads:\n"
                  Thread.list.each do |thr|
                    f.puts "#{thr.inspect}"
                    f.puts "   iType: #{thr == Thread.main ? :main_thread : thr[:itype] || :uncategorized}"
                    f.puts "   Group: #{thr.group}"
                    f.puts "  T-Vars: #{thr.thread_variables.inspect}"
                    thr.thread_variables.each {|k| f.puts "          #{k} => #{thr.thread_variable(k)}" }
                    f.puts "  F-Vars: #{thr.keys.inspect}"
                    thr.keys.each {|k| f.puts "          #{k} => #{thr[k]}" }
                  end
                end
                fork { exec("subl -w #{Shellwords.shellescape dump_file} && rm #{Shellwords.shellescape dump_file}") }
              else
                addstr "#{ch}\n"
              end
            end
          end
        end if @app.opts[:window_keypad]
      end

      def stop_loop
        return unless @loop
        @loop[:stop] = true
        @loop.join
        if @keyloop
          @keyloop[:monitor].synchronize do
            @keyloop.try(:kill)
          end
        end
      end

      def line l = 1
        setpos(l - 1, 0)
      end

      [:red, :blue, :yellow, :cyan, :magenta, :gray, :green, :white].each do |c|
        define_method(c) do |*args, &block|
          color = self.class.const_get "COLOR_#{c.to_s.upcase}"
          attron(color_pair(color)|A_NORMAL) do
            if block
              block.call
            else
              args.each {|a| addstr(a) }
            end
          end
        end
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
        Thread.current[:last_render_duration] = rt = Benchmark.realtime do
          @monitor.synchronize do
            @t += 1
            update { __send__(:"_view_#{@view}") }
          end
        end
        if rt > 0.020
          Thread.main[:app].warning "window render took: #{"%.6f" % rt}"
        else
          Thread.main[:app].debug "window render took: #{"%.6f" % rt}", 125
        end
      rescue StandardError => ex
        Thread.main[:app].notify_exception("DbSucker::Window encountered an render error on tick ##{@t}", ex)

        update do
          next_line
          red "RenderError occured!"
          next_line
          red "#{ex.class}: #{ex.message}"
          ex.backtrace.each do |l|
            next_line
            red("    #{l}")
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
        if @app.opts[:window_keypad]
          noecho
          cbreak
          # raw
          stdscr.keypad = true
        end

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

      def _view_status
        next_line
        yellow "        Status: "
        send(sklaventreiber.status[1].presence || :blue, sklaventreiber.status[0])
        # shutdown message
        if $core_runtime_exiting && sklaventreiber.status[0] != "terminated"
          red " (HALTING … please wait)"
        end

        next_line
        yellow "       Threads: "
        blue "#{Thread.list.length} ".ljust(COL1, " ")

        next_line
        yellow "       Started: "
        blue "#{@app.boot}"
        yellow " ("
        blue human_seconds(Time.current - app.boot)
        yellow ")"

        next_line
        yellow "Transaction ID: "
        cyan sklaventreiber.trxid

        next_line
        yellow "      Database: "
        magenta sklaventreiber.data[:database] || "?"
        yellow " (transfering "
        blue "#{sklaventreiber.data[:tables_transfer] || "?"}"
        yellow " of "
        blue "#{sklaventreiber.data[:tables_total] || "?"}"
        yellow " tables)"

        next_line
        total, done = sklaventreiber.data[:tables_transfer], sklaventreiber.data[:tables_done]
        perc = total && done ? f_percentage(done, total) : "?"
        yellow "      Progress: "
        green perc
        yellow " – "
        blue "#{done}/#{total || "?"} workers done"

        _render_workers
      end

      def _render_workers
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
              yellow "… #{rest.length} more [#{part.join(", ")}]"
              break
            end
            _render_worker_line(w)
          end
        end
      end

      def _render_worker_line worker
        next_line
        col1 = sklaventreiber.data[:window_col1]
        col2 = sklaventreiber.data[:window_col2]

        # status icon
        case worker.state
          when :pending then gray("⊙")
          when :aquired then white("⊙")
          when :done then green("✔")
          when :failed then red("✘")
          when :canceled then red("⊘")
          when :running then
            c = case @t % 4
              when 0 then "◜" # "╭"
              when 1 then "◝" # "╮"
              when 2 then "◞" # "╯"
              when 3 then "◟" # "╰"
            end
            yellow "#{c}"
        end

        # table_name
        send(worker.should_cancel ? :red : :magenta, " #{worker.table}".ljust(col1 + 1, " "))
        gray " | "

        # status
        if worker.step
          cyan "[#{worker.step}/#{worker.perform.length}] "
        end
        if worker.status[0].respond_to?(:to_curses)
          worker.status[0].to_curses(self)
        else
          send(worker.status[1].presence || :blue, uncolorize("#{worker.status[0]}"))
        end
      end

      # used to render everything before exiting, can't fucking dump the pads I tried to implement -.-"
      def _render_final_results
        t_db, t_total, t_done = sklaventreiber.data[:database], sklaventreiber.data[:tables_transfer], sklaventreiber.data[:tables_done]
        perc = t_total && t_done ? f_percentage(t_done, t_total) : "?"

        puts
        puts c("        Status: ") << c(sklaventreiber.status[0], sklaventreiber.status[1].presence || "red")
        puts c("       Threads: ") << c("#{Thread.list.length} ".ljust(COL1, " "), :blue)
        puts c("       Started: ") << c("#{@app.boot}", :blue) << c(" (") << c(human_seconds(Time.current - app.boot), :blue) << c(")")
        puts c("Transaction ID: ") << c("#{sklaventreiber.trxid}", :cyan)
        puts c("      Database: ") << c(t_db || "?", :magenta) << c(" (transferred ") << c(t_total || "?", :blue) << c(" of ") << c(t_done || "?", :blue) << c(" tables)")
        puts c("      Progress: ") << c(perc, :green) << c(" – ") << c(t_total || "?", :blue) << c("#{t_done}/#{t_total || "?"} workers done", :blue)

        if sklaventreiber.workers.any?
          puts
          enum = sklaventreiber.workers.sort_by{|w| [w.priority, w.table] }
          enum.each do |worker|
            col1 = sklaventreiber.data[:window_col1]
            col2 = sklaventreiber.data[:window_col2]

            puts "".tap{|res|
              # status icon
              res << case worker.state
                when :pending then c("⊙", :black)
                when :aquired then c("⊙", :white)
                when :done then c("✔", :green)
                when :failed then c("✘", :red)
                when :canceled then c("⊘", :red)
              end
              # table
              res << c(" #{worker.table}".ljust(col1 + 1, " "), :magenta) << c(" | ", :black)
              # steps
              res << c("[#{worker.step}/#{worker.perform.length}] ", :cyan) if worker.step
              # status
              res << c(worker.status[0], worker.status[1].presence || :blue)
            }
          end
          puts
        end
      end
    end
  end
end
