module DbSucker
  class Application
    class Window
      class Prompt
        attr_reader :cpos, :label, :buffer

        def initialize window, keypad
          @window = window
          @keypad = keypad
          reset_state(true)
        end

        def active?
          @active
        end

        def interactive?
          active? && @callback
        end

        def reset_state initializing = false
          unless initializing
            @window.set_cursor(0)
            @keypad.app.fire(:prompt_stop, @label)
            @window.force_cursor(nil)
          end
          @active = false
          @buffer = ""
          @label = nil
          @callback = nil
          @cpos = 0
        end

        def set! label, &callback
          @label = label
          @callback = callback
          @active = true
          @window.set_cursor(2)
          @keypad.app.fire(:prompt_start, @label)
        end

        def render target, line
          _this = self
          target.instance_eval do
            return unless _this.active?
            setpos(line, 0)
            clrtoeol
            setpos(line, 0)
            blue(_this.label)
            white(_this.buffer)
            force_cursor(line, stdscr.curx + _this.cpos)
          end
        end

        def handle_input ch
          case ch
          when 27 then _escape
          when 127 then _backspace
          when 330 then _delete
          when 260 then _left_arrow
          when 261 then _right_arrow
          when 13 then _enter
          else
            #@buffer.concat(ch.bytes.to_s)
            @cpos.zero? ? @buffer.concat(ch) : @buffer.insert(@cpos - 1, ch)
          end
        end

        def _escape
          reset_state
        end

        def _backspace
          @buffer.slice!(@cpos - 1)
        end

        def _delete
          return if @cpos.zero?
          @buffer.slice!(@cpos)
          @cpos += 1
        end

        def _left_arrow
          @cpos = [@cpos - 1, -@buffer.length].max
        end

        def _right_arrow
          @cpos = [@cpos + 1, 0].min
        end

        def _enter
          @callback.call(@buffer)
          reset_state
        end
      end
    end
  end
end
