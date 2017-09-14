module DbSucker
  class Application
    class Window
      class Prompt
        def initialize window, keypad
          @window = window
          @keypad = keypad
          reset_state
        end

        def active?
          @active
        end

        def interactive?
          active? && @callback
        end

        def reset_state
          @active = false
          @buffer = ""
          @label = nil
          @callback = nil
        end

        def set! label, &callback
          @label = label
          @callback = callback
          @active = true
        end

        def render target, line
          _label = @label
          _buffer = @buffer
          _active = active?
          target.instance_eval do
            return unless _active
            setpos(line, 0)
            clrtoeol
            setpos(line, 0)
            blue(_label)
            white(_buffer)
          end
        end

        def handle_input ch
          case ch
          when 27 # escape
            reset_state
          when 127 # backspace
            @buffer.slice!(-1)
          when 13 # enter
            @callback.call(@buffer)
            reset_state
          else
            @buffer << ch
          end
        end
      end
    end
  end
end
