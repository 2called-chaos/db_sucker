module DbSucker
  module Patches
    class BetaWarning < Application::Tie
      AcceptedContinue = Class.new(::StandardError)

      def self.hook!(app)
        app.send(:extend, DispatchOverrides)
      end

      module WindowExtensions
        def _view_beta_warning
          # render monkey
          current_frame = monkey_frames[@tick % 16 / 2]

          cyan "  " << "    ||      ||".ljust(33, " ")
          current_frame.each do |line|
            y = true
            yellow "  "
            line.split(/(�[^�]+�)/).each do |m|
              send(y ? :cyan : :green, m.tr("�", ""))
              y = !y
            end

            next_line
            break if @line > lines - 1
          end
          (lines - @line).times do |i|
            inset = i % 3 == 0 ? "======" : "      "
            cyan "  " << "    ||#{inset}||".ljust(33, " ")
            next_line
          end

          # render text
          @line = -1
          self.x_offset = 24

          font_frame.each do |line|
            red line.ljust(30, " ")
            next_line
          end

          self.x_offset = 37
          next_line

          dialog! do |d|
            d.border_color = :gray
            d.line "DbSucker v3 is a complete rewrite and has few testers.", :blue
            d.line "If you encounter issues, have suggestions or want to", :blue
            d.line "add support for other DBMS please let me know on Github!", :blue
            d.br
            d.line "https://github.com/2called-chaos/db_sucker", :cyan
            d.hr
            d.line "I swear that I have backups before testing this tool and", :red
            d.line "that I won't beat the cute monkey if something goes south", :red
            d.br
            d.button_group(5) do |g|
              g << d.build_button("ABORT (n/f/0/q/ESC)", :yellow)
              g << d.build_button("ACCEPT & CONTINUE (y/t/1)", :green)
            end
          end

          if lines < 27 || cols < 98
            setpos(0, 0)
            red "INCREASE WINDOW SIZE!"
          end
        end

        def frames
          @frames ||= File.read(__FILE__).split("__END__").last.split("-----").map{|frame| frame.split("\n") }
        end

        def font_frame
          frames[0]
        end

        def monkey_frames
          frames[1..-1]
        end
      end

      module DispatchOverrides
        def _suck_variation identifier, ctn, variation, var
          touch_file = "#{core_cfg_path}/.beta-warning"
          return super if File.exist?(touch_file)

          begin
            _thr = Thread.current
            begin
              trap_signals
              @sklaventreiber = Application::SklavenTreiber.new(self, uniqid)
              @sklaventreiber.spooled do
                begin
                  @sklaventreiber._init_window
                  @sklaventreiber.window.force_kill = true
                  @sklaventreiber.window.send(:extend, WindowExtensions)

                  view_was = @sklaventreiber.window.change_view(:beta_warning)
                  @sklaventreiber.window.keypad.prompt!("[press any key to return]",
                    return_on_buffer: Proc.new{|b, c| %w[y t 1 n f 0 q 27].include?(c.to_s.downcase) },
                    capture_enter: false,
                    has_cursor: false,
                    capture_escape: false,
                    cursor_visible: false
                  ) do |response|
                    if %w[y t 1].include?(response)
                      FileUtils.mkdir_p(File.dirname(touch_file))
                      FileUtils.touch(touch_file)
                      _thr.raise(AcceptedContinue)
                    else
                      $core_runtime_exiting = 1
                    end
                  end

                  loop do
                    break if $core_runtime_exiting
                    sleep 0.1
                  end
                ensure
                  sandboxed { @sklaventreiber.window.try(:stop) }
                end
              end
            ensure
              release_signals
            end

            throw :dispatch_handled
          rescue AcceptedContinue
            super
          end
        end
      end
    end
  end
end

__END__
 ____  ______ _______       _
|  _ \|  ____|__   __|/\   | |
| |_) | |__     | |  /  \  | |
|  _ <|  __|    | | / /\ \ | |
| |_) | |____   | |/ ____ \|_|
|____/|______|  |_/_/    \_(_)
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \       ,,,,�
    ||  �\(|o  o /`,|)    _/,,,/�
    ||   �\/ "   \`,_)   (_` ,/�
    ||====�\ U   /_/      /, /�
    ||    �/`--'`-`-,,,,,/` /�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /\�
    �/  _____,(   \\\�
   �/  /     �||�\   \\\�
  �,`-/�======||� ,  ) ||�
 �/ '_)      �||�/  / //�
�/  /�||      |�/  / ||�
�\_/ �||======�(_` \  \\ ,-.�
    ||      ||�\  \  \`-'/�
    ||      ||� \_|   `"`�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \   ,,,,�
    ||  �\(|o  o /`,|)  |,,,|�
    ||   �\/ "   \`,_) (_` ,|�
    ||====�\ U   /_/     |,|�
    ||    �/`--'`-`-,,,,,|`|�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /;�
    �/  _____,(   \ \\�
   �/  /�     ||�\   \ \\�
  �,`-/�======||� ,  )  ||�
 �/ '_)�      ||�/  /  //�
�/  /�||      |�/  /  ||�
�\_/� ||======�(_` \  ||   ,�
    ||      ||�\  \  \\_//�
    ||      ||� \_|   \-/�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \,,,,�
    ||  �\(|o  o /`,|\,,,\�
    ||   �\/ "   \`,_(_` ,\�
    ||====�\ U   /_/    \, \�
    ||    �/`--'`-`-,,,,,\` |�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /;�
    �/  _____,(   \ \\�
   �/  /�     ||�\   \ \\�
  �,`-/�======||� ,  )  \\�
 �/ '_)�      ||�/  /   ||�
�/  /�||      |�/  /    ||�
�\_/� ||======�(_` \    ||�
    ||      ||�\  \   \\,,,,�
    ||      ||� \_|    \----'�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \   ,,,,�
    ||  �\(|o  o /`,|)  |,,,|�
    ||   �\/ "   \`,_) (_` ,|�
    ||====�\ U   /_/     |,|�
    ||    �/`--'`-`-,,,,,|`|�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /\�
    �/  _____,(   \\\�
   �/  /�     ||�\   \\\�
  �,`-/�======||� ,  ) ||�
 �/ '_)�      ||�/  / //�
�/  /�||      |�/  / ||�
�\_/� ||======�(_` \  \\�
    ||      ||�\  \  \\�
    ||      || �\_|   \\�
    ||======||        �\\,,�
    ||      ||         �\-'�
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \       ,,,,�
    ||  �\(|o  o /`,|)    _/,,,/�
    ||   �\/ "   \`,_)   (_` ,/�
    ||====�\ U   /_/      /, /�
    ||    �/`--'`-`-,,,,,/` /�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /\�
    �/  _____,(   \\\�
   �/  /�     ||�\   \\\�
  �,`-/�======||� ,  ) ||�
 �/ '_)�      ||�/  / //�
�/  /�||      |�/  / ||�
�\_/� ||======�(_` \  \\ ,-.�
    ||      ||�\  \  \`-'/�
    ||      || �\_|   `"`�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \   ,,,,�
    ||  �\(|o  o /`,|)  |,,,|�
    ||   �\/ "   \`,_) (_` ,|�
    ||====�\ U   /_/     |,|�
    ||    �/`--'`-`-,,,,,|`|�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /;�
    �/  _____,(   \ \\�
   �/  /�     ||�\   \ \\�
  �,`-/�======|| �,  )  ||�
 �/ '_)�      ||�/  /  //�
�/  /�||      |�/  /  ||�
�\_/� ||======�(_` \  ||   ,�
    ||      ||�\  \  \\_//�
    ||      || �\_|   \-/�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \,,,,�
    ||  �\(|-  - /`,|\,,,\�
    ||   �\/ "   \`,_(_` ,\�
    ||====�\ U   /_/    \, \�
    ||    �/`--'`-`-,,,,,\` |�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /;�
    �/  _____,(   \ \\�
   �/  /�     ||�\   \ \\�
  �,`-/�======|| �,  )  \\�
 �/ '_)�      ||�/  /   ||�
�/  /�||      |�/  /    ||�
�\_/� ||======�(_` \    ||�
    ||      ||�\  \   \\,,,,�
    ||      || �\_|    \----'�
    ||======||
    ||      ||
    ||      ||
-----
    ||      ||
    ||======||
    ||      ||
    ||�___�   ||
    ||�\_`\�==||
    |�(`__/�  ||
    || �\ \  :-"""-.�
    ||=�|  \/-=-.,` \   ,,,,�
    ||  �\(|o  o /`,|)  |,,,|�
    ||   �\/ "   \`,_) (_` ,|�
    ||====�\ U   /_/     |,|�
    ||    �/`--'`-`-,,,,,|`|�
    ||   �(        ` ______/�
    ||===�(`_/\_` ) /�
    ||   �|        |�
    ||    �\' " "  /�
    |�'````` "''_ /\�
    �/  _____,(   \\\�
   �/  /�     ||�\   \\\�
  �,`-/�======|| �,  ) ||�
 �/ '_)�      ||�/  / //�
�/  /�||      |�/  / ||�
�\_/� ||======�(_` \  \\�
    ||      ||�\  \  \\�
    ||      || �\_|   \\�
    ||======||        �\\,,�
    ||      ||         �\-'�
    ||      ||
