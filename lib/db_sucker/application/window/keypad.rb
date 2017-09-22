module DbSucker
  class Application
    class Window
      class Keypad
        include Core
        attr_reader :prompt, :keyloop, :window

        def initialize window
          @window = window
          @prompt = Prompt.new(@window, self)
          @monitor = Monitor.new
        end

        HELP_INFO = {
          key_bindings: [
            ["?", "shows this help"],
            ["^", "eval prompt (app context, synchronized)"],
            ["P", "kill SSH polling (if it stucks)"],
            ["T", "create core dump and open in editor"],
            ["q", "quit prompt"],
            ["Q", "same as ctrl-c"],
            [":", "main prompt"],
          ],
          main_commands: [
            [["?", %w[h elp]], [], "shows this help"],
            [[%w[q uit]], [], "quit prompt"],
            [["q!", "quit!"], [], "same as ctrl-c"],
            [["dump"], [], "create and open coredump"],
            [["eval"], [[:optional, "code"]], "executes code or opens eval prompt (app context, synchronized)"],
            [[%w[c ancel]], [[:mandatory, %w[table_name --all]]], "cancels given or all workers"],
            [[%w[p ause]], [[:mandatory, %w[table_name --all]]], "pauses given or all workers"],
            [[%w[r esume]], [[:mandatory, %w[table_name --all]]], "resumes given or all workers"],
          ],
        }

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

        def main_prompt
          prompt!(":") do |raw|
            break if raw.blank?
            args = raw.split(" ")
            cmd = args.shift
            case cmd
              when "?", "h", "help" then show_help
              when "c", "cancel" then cancel_workers(args)
              when "q", "quit" then quit_dialog
              when "q!", "quit!" then $core_runtime_exiting = 1
              when "dump" then dump_core
              when "eval" then args.any? ? _eval(args.join(" ")) : eval_prompt
              when "p", "pause" then pause_workers(args)
              when "r", "resume" then resume_workers(args)
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
          prompt!(q,
            prompt: p,
            return_on_buffer: true,
            capture_enter: false,
            has_cursor: false
          ) do |response|
            if response == "q" || @window.strbool(response) == true
              $core_runtime_exiting = 1
            end
          end
        end

        def show_help
          view_was = window.change_view(:help)
          prompt!("[press any key to return]",
            return_on_buffer: true,
            capture_enter: false,
            has_cursor: false,
            capture_escape: false,
            cursor_visible: false
          ) do |response|
            window.change_view(view_was)
          end
        end

        def pause_workers args
          if args[0].is_a?(String)
            _detect_worker(args.join(" "), &:pause)
          else
            prompt!("Usage: :p(ause) <table_name|--all>", color: :yellow)
          end
        end

        def resume_workers args
          if args[0].is_a?(String)
            _detect_worker(args.join(" "), &:unpause)
          else
            prompt!("Usage: :r(esume) <table_name|--all>", color: :yellow)
          end
        end

        def cancel_workers args
          if args[0].is_a?(String)
            _detect_worker(args.join(" ")) do |wrk|
              wrk.cancel! "canceled by user"
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

