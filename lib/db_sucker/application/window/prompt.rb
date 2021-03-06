module DbSucker
  class Application
    class Window
      class Prompt
        attr_reader :cpos, :label, :buffer, :opts

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
          @opts = {
            color: :blue,
            return_on_buffer: false,
            capture_enter: true,
            capture_escape: true,
            has_cursor: true,
            prompt: nil, # proc
            cursor_visible: true,
          }
        end

        def set! label, opts = {}, &callback
          @label = label
          @callback = callback
          @active = true
          @opts = @opts.merge(opts)
          @keypad.app.fire(:prompt_start, @label, @opts)
          @window.set_cursor(@opts[:cursor_visible] ? 2 : 0)
        end

        def render target, line
          _this = self
          target.instance_eval do
            return unless _this.active?
            setpos(line, 0)
            clrtoeol
            setpos(line, 0)
            if _this.opts[:prompt]
              instance_eval(&_this.opts[:prompt])
            else
              send(_this.opts[:color], _this.label)
            end
            white(_this.buffer)
            force_cursor(line, stdscr.curx + _this.cpos)
          end
        end

        def handle_input ch
          case ch
            when 27 then (@opts[:capture_escape] ? _escape : sbuf(ch))
            when 127 then (@opts[:has_cursor] ? _backspace : sbuf(ch))
            when 330 then (@opts[:has_cursor] ? _delete : sbuf(ch))
            when 260 then (@opts[:has_cursor] ? _left_arrow : sbuf(ch))
            when 261 then (@opts[:has_cursor] ? _right_arrow : sbuf(ch))
            when 13 then (@opts[:capture_enter] ? _enter : sbuf(ch))
            else sbuf(ch)
          end
        end

        def sbuf ch
          #@buffer.concat(ch.bytes.to_s)
          @cpos.zero? ? @buffer.concat(ch) : @buffer.insert(@cpos - 1, ch)
          if @opts[:return_on_buffer].is_a?(Regexp)
            _enter if @buffer.match(@opts[:return_on_buffer])
          elsif @opts[:return_on_buffer].is_a?(Proc)
            _enter if @opts[:return_on_buffer].call(@buffer, ch)
          elsif @opts[:return_on_buffer]
            _enter
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
          _b = @buffer
          _c = @callback
          reset_state
          _c.call(_b)
        end
      end
    end
  end
end
