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

      def _view_help
        _render_status(threads: false, started: false, trxid: false, database: false)

        #next_line; next_line
        #magenta "db_sucker"
        #blue " #{VERSION}"
        #yellow " – "
        #cyan "(C) 2016-#{Time.current.year} Sven Pachnit (bmonkeys.net)"

        #next_line
        #gray "Released under the MIT license."

        next_line; next_line
        blue "Key Bindings (case sensitive):"
        next_line

        Keypad::HELP_INFO[:key_bindings].each do |key, desc|
          next_line
          magenta "    #{key}"
          yellow "  #{desc}"
        end

        next_line; next_line
        blue "Main prompt commands:"
        next_line

        # only build output once and save it in memory
        @_view_help_memory ||= begin
          mchp = Keypad::HELP_INFO[:main_commands].map do |aliases, options, desc|
            [].tap do |result|
              result << [].tap{|r|
                aliases.each do |al|
                  r << (al.is_a?(Array) ? al.join("").length + 4 : al.length + 2)
                end
              }.sum

              result << [].tap{|r|
                options.each do |type, name|
                  r << (type == :mandatory ? "<#{[*name] * "|"}> " : "[#{[*name] * "|"}] ").length
                end
              }.sum
            end
          end
          columns = { aliases: mchp.map(&:first).max, options: mchp.map(&:second).max }

          # render commands
          [].tap do |instruct|
            Keypad::HELP_INFO[:main_commands].each do |aliases, options, desc|
              # aliases
              instruct << [:next_line]
              instruct << [:addstr, "    "]
              cl = 0
              aliases.each do |al|
                instruct << [:magenta, ":"]
                if al.is_a?(Array)
                  instruct << [:blue, "#{al[0]}"]
                  instruct << [:gray, "("]
                  instruct << [:cyan, "#{al[1]}"]
                  cl += al.join("").length + 4
                  instruct << [:gray, ") "]
                else
                  cl += al.length + 2
                  instruct << [:blue, "#{al} "]
                end
              end
              instruct << [:addstr, "".ljust(columns[:aliases] - cl, " ")]

              # options
              cl = 0
              instruct << [:addstr, " "]
              options.each do |type, name|
                if type == :mandatory
                  instruct << [:red, "<"]
                  [*name].each_with_index do |n, i|
                    instruct << [:gray, "|"] if i > 0
                    instruct << [:blue, n]
                  end
                  instruct << [:red, "> "]
                else
                  instruct << [:yellow, "["]
                  [*name].each_with_index do |n, i|
                    instruct << [:gray, "|"] if i > 0
                    instruct << [:cyan, n]
                  end
                  instruct << [:yellow, "] "]
                end
                cl += [*name].join("").length + 3 + [*name].length - 1
              end
              instruct << [:addstr, "".ljust(columns[:options] - cl, " ")]

              instruct << [:yellow, " #{desc}"]
            end
          end
        end

        @_view_help_memory.each do |a|
          send(*a)
        end

        @keypad.prompt.render(self, lines-1)
      end

      def _view_status
        _render_status
        _render_workers
        @keypad.prompt.render(self, lines-1)
      end

      def _render_status opts = {}
        opts = opts.reverse_merge(status: true, threads: true, started: true, trxid: true, database: true, progress: true)

        if opts[:status]
          next_line
          yellow "        Status: "
          send(sklaventreiber.status[1].presence || :blue, sklaventreiber.status[0])
          # shutdown message
          if $core_runtime_exiting && sklaventreiber.status[0] != "terminated"
            red " (HALTING … please wait)"
          end
        end

        if opts[:threads]
          next_line
          yellow "       Threads: "
          blue "#{Thread.list.length} ".ljust(COL1, " ")
        end

        if opts[:started]
          next_line
          yellow "       Started: "
          blue "#{@app.boot}"
          yellow " ("
          blue human_seconds(Time.current - app.boot)
          yellow ")"
        end

        if opts[:trxid]
          next_line
          yellow "Transaction ID: "
          cyan sklaventreiber.trxid
        end

        if opts[:database]
          next_line
          yellow "      Database: "
          magenta sklaventreiber.data[:database] || "?"
          yellow " (transfering "
          blue "#{sklaventreiber.data[:tables_transfer] || "?"}"
          yellow " of "
          blue "#{sklaventreiber.data[:tables_total] || "?"}"
          yellow " tables)"
        end

        if opts[:progress]
          next_line
          total, done = sklaventreiber.data[:tables_transfer], sklaventreiber.data[:tables_done]
          perc = total && done ? f_percentage(done, total) : "?"
          yellow "      Progress: "
          green perc
          yellow " – "
          blue "#{done}/#{total || "?"} workers done"
        end
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
          when :pausing, :paused then gray("♨")
          when :aquired then white("⊙")
          when :done then green("✔")
          when :failed then red("✘")
          when :canceled then red("⊘")
          when :running then yellow("#{worker.spinner_frame}")
        end

        # table_name
        send(worker.should_cancel ? :red : worker.paused? ? :gray : :magenta, " #{worker.table}".ljust(col1 + 1, " "))
        gray " | "

        # status
        if worker.step
          cyan "[#{worker.step}/#{worker.perform.length}] "
        end
        if worker.status[0].respond_to?(:to_curses)
          worker.status[0].to_curses(self)
        else
          send(worker.status[1].presence || :blue, decolorize("#{worker.status[0]}"))
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
                when :done then c("✔", :green)
                when :failed then c("✘", :red)
                when :canceled then c("⊘", :red)
                else "#{worker.state.inspect}"
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
