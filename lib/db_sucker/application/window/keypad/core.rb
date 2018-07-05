module DbSucker
  class Application
    class Window
      class Keypad
        module Core
          def sync &block
            @monitor.synchronize(&block)
          end

          def sklaventreiber
            @window.sklaventreiber
          end

          def app
            @window.app
          end

          def enabled?
            app.opts[:window_keypad]
          end

          def start_loop
            return false unless enabled?
            @keyloop = app.spawn_thread(:window_keypad_loop) do |thr|
              loop {
                begin
                  handle_input(@window.send(:getch))
                rescue StandardError => ex
                  app.notify_exception("DbSucker::Window::Keypad encountered an input handle error on tick ##{@window.tick}", ex)
                end
              }
            end
          end

          def stop_loop
            return unless @keyloop
            sync { @keyloop.kill }
            @keyloop.join
          end

          def prompt! *a, &b
            return false unless enabled?
            @prompt.set!(*a, &b)
          end

          def _detect_worker arg, &block
            sklaventreiber.sync do
              if arg == "--all"
                sklaventreiber.workers.each{|w| block.call(w) }
              else
                wrk = sklaventreiber.workers.detect do |w|
                  if arg.start_with?("^")
                    w.table.match(/#{arg}/i)
                  elsif arg.start_with?("/")
                    w.table.match(/#{arg[1..-1]}/i)
                  else
                    w.table == arg
                  end
                end
                if wrk
                  block.call(wrk)
                else
                  prompt!("Could not find any worker by the pattern `#{arg}'", color: :red)
                end
              end
            end
          end

          def _eval evil
            return if evil.blank?
            app.dump_file "eval-result", true do |f|
              begin
                f.puts("#{evil}\n\n")
                f.puts(app.sync{ app.instance_eval(evil) })
              rescue Exception => ex
                f.puts("#{ex.class}: #{ex.message}")
                ex.backtrace.each {|l| f.puts("  #{l}") }
              end
            end
          end
        end
      end
    end
  end
end
