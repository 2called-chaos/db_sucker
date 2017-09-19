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

        def handle_input ch
          sync do
            if @prompt.interactive?
              @prompt.handle_input(ch)
            else
              case ch
              when ":" then main_prompt
              when "^" then eval_prompt # (@development)
              when "T" then dump_core # (@development)
              when "P" then kill_ssh_poll
              when "?" then show_help
              when "q" then quit_dialog
              when "Q" then $core_runtime_exiting = 1
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
            rescue StandardError => ex
              f.puts("#{ex.class}: #{ex.message}")
              ex.backtrace.each {|l| f.puts("  #{l}") }
            end
          end
        end

        def eval_prompt
          prompt!("eval> ") {|evil| _eval(evil) }
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

        def show_help

        end

        def main_prompt
          prompt!(":") do |raw|
            break if raw.blank?
            args = raw.split(" ")
            cmd = args.shift
            case cmd
              when "c", "cancel" then cancel_workers(args)
              when "q", "quit" then quit_dialog
              when "q!", "quit!" then $core_runtime_exiting = 1
              when "dump" then dump_core
              when "eval" then args.any? ? _eval(args.join(" ")) : eval_prompt
            end
          end
        end

        def cancel_workers args
          if args[0].is_a?(String)
            sklaventreiber.sync do
              if args[0] == "--all"
                sklaventreiber.workers.each{|w| w.cancel! "canceled by user" }
              else
                # find worker
                wrk = sklaventreiber.workers.detect do |w|
                  if args[0].start_with?("^")
                    w.table.match(/#{args[0]}/i)
                  elsif args[0].start_with?("/")
                    w.table.match(/#{args[0][1..-1]}/i)
                  else
                    w.table == args[0]
                  end
                end
                if wrk
                  catch(:abort_execution) { wrk.cancel!("canceled by user") }
                else
                  prompt!("Could not find any worker by the pattern `#{args[0]}'", color: :red)
                end
              end
            end
          else
            prompt!("Usage: :c(cancel) <table_name|--all>", color: :yellow)
          end
        end

        def kill_ssh_poll
          return unless sklaventreiber.workers.select{|w| !w.done? || w.sshing }.any?
          sklaventreiber.poll.try(:kill)
        end

        def dump_core
          app.dump_core
        end
      end
    end
  end
end

