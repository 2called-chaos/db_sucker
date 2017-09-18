module DbSucker
  class Application
    class Window
      include Core
      include Curses
      COLOR_GRAY = 8
      COL1 = 20
      COL2 = 25
      COL3 = 20
      OutputHelper.hook(self)

      attr_reader :app, :sklaventreiber, :keypad, :tick, :spinner_frames
      attr_accessor :view

      def initialize app, sklaventreiber
        @app = app
        @keypad = Keypad.new(self)
        @sklaventreiber = sklaventreiber
        @monitor = Monitor.new
        @line = 0
        @tick = 0
        @view = :status
        choose_spinner
      end

      def refresh_screen
        Thread.current[:last_render_duration] = rt = Benchmark.realtime do
          @monitor.synchronize do
            @tick += 1
            update { __send__(:"_view_#{@view}") }
          end
        end
        if rt > 0.020
          @app.warning "window render took: #{"%.6f" % rt}"
        else
          @app.debug "window render took: #{"%.6f" % rt}", 125
        end
      rescue StandardError => ex
        @app.notify_exception("DbSucker::Window encountered an render error on tick ##{@tick}", ex)

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
        Thread.current.wait(1)
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
        @keypad.prompt.render(self, lines-1)
      end

      def _render_workers
        if sklaventreiber.workers.any?
          next_line
          limit = lines - @line - 3 - (@keypad.prompt.active? ? 1 : 0) # @l starting at 0, 1 for blank line to come, placeholder
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
          when :running then yellow("#{worker.spinner_frame}")
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
