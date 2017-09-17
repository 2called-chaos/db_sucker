module DbSucker
  class Application
    class Window
      class Keypad
        attr_reader :prompt, :keyloop

        def initialize window
          @window = window
          @prompt = Prompt.new(@window, self)
          @monitor = Monitor.new
        end

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
          @keyloop = Thread.new do
            Thread.current[:itype] = :window_keypad_loop
            Thread.current.priority = app.opts[:tp_window_keypad_loop]
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

        def handle_input ch
          sync do
            if @prompt.interactive?
              @prompt.handle_input(ch)
            else
              case ch
              when "^" then eval_prompt # (development)
              when ":" then main_prompt
              when "T" then dump_core # (development)
              when "P" then kill_ssh_poll
              when "q" then quit_dialog
              when "Q" then $core_runtime_exiting = 1
              end
            end
          end
        end

        def eval_prompt
          prompt!("eval> ") do |evil|
            break if evil.blank?
            app.dump_file "eval-result", true do |f|
              begin
                f.puts("#{evil}\n\n")
                f.puts(app.sync{ app.instance_eval(evil) })
              rescue StandardError => ex
                f.puts("#{ex.class}: #{ex.message}")
                ex.backtrace.each {|l| f.puts("  #{l}") }
              end
            end
          end
        end

        def quit_dialog
          q = "Do you want to abort all operations and quit?"
          p = Proc.new do
            blue q
            gray " [y/q/t/1 n/f/0] "
          end
          prompt!(q, prompt: p, return_on_buffer: true, return_on_enter: false, has_cursor: false) do |response|
            if response == "q" || @window.strbool(response) == true
              $core_runtime_exiting = 1
            end
          end
        end
        def main_prompt
          prompt!(":") do |evil|
            break if evil.blank?
            # app.dump_file "eval-result", true do |f|
            #   begin
            #     f.puts("#{evil}\n\n")
            #     f.puts(app.sync{ app.instance_eval(evil) })
            #   rescue StandardError => ex
            #     f.puts("#{ex.class}: #{ex.message}")
            #     ex.backtrace.each {|l| f.puts("  #{l}") }
            #   end
            # end
          end
        end

        def kill_ssh_poll
          return unless sklaventreiber.workers.select{|w| !w.done? || w.sshing }.any?
          sklaventreiber.poll.try(:kill)
        end

        def dump_core
          app.dump_file "coredump", true do |f|
            # thread info
            f.puts "#{Thread.list.length} threads:\n"
            Thread.list.each do |thr|
              f.puts "#{thr.inspect}"
              f.puts "   iType: #{thr == Thread.main ? :main_thread : thr[:itype] || :uncategorized}"
              f.puts "Priority: #{thr.priority}"
              f.puts "  T-Vars: #{thr.thread_variables.inspect}"
              thr.thread_variables.each {|k| f.puts "          #{k} => #{thr.thread_variable(k)}" }
              f.puts "  F-Vars: #{thr.keys.inspect}"
              thr.keys.each {|k| f.puts "          #{k} => #{thr[k]}" }
            end

            # worker info
            f.puts "\n\n#{sklaventreiber.workers.length} workers:\n"
            sklaventreiber.workers.each do |w|
              f.puts "#{"[SSH] " if w.sshing} #{w.descriptive} #{w.state}".strip
            end
          end
        end
      end
    end
  end
end

