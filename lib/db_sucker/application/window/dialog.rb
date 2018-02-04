module DbSucker
  class Application
    class Window
      class Dialog
        attr_accessor :border_color

        BOX = {
          tl: "┌",
          t: "─",
          tr: "┐",
          l: "│",
          r: "│",
          bl: "└",
          b: "─",
          br: "┘",
          hrl: "├",
          hr: "─",
          hrr: "┤",
        }

        def initialize window, &block
          @window = window
          @width = false
          @border_color = :yellow
          @border_padding = 1
          @separator_padding = 1
          @lines = []
          block.call(self)
        end

        def line str = nil, color = :yellow, &block
          if block
            @lines << [].tap{|a| block.call(a) }
          else
            @lines << [[str, color]]
          end
        end

        def br
          @lines << []
        end

        def hr
          @lines << :hr
        end

        def button *a
          @lines.concat(build_button(*a))
        end

        def build_button str, color = :yellow
          tl = BOX[:tl]
          t = BOX[:t]
          tr = BOX[:tr]
          l = BOX[:l]
          r = BOX[:r]
          bl = BOX[:bl]
          b = BOX[:b]
          br = BOX[:br]
          width = str.length + 2
          [].tap do |a|
            a << [["#{tl}" << "".ljust(width, t) << "#{tr}", color]]
            a << [["#{l}" << " #{str} ".ljust(width, t) << "#{r}", color]]
            a << [["#{bl}" << "".ljust(width, b) << "#{br}", color]]
          end
        end

        def button_group buttons = [], spaces = 2, &block
          spaces = buttons if block
          btns = block ? [].tap{|a| block.call(a) } : buttons.dup
          spaces = "".ljust(spaces, " ")
          first = btns.shift

          btns.each_with_index do |lines, bi|
            lines.each_with_index do |l, i|
              first[i] << [spaces, :yellow]
              first[i].concat(l)
            end
          end

          @lines.concat first
        end

        # -----------------------------------------------------------

        def _nl
          @window.next_line
        end

        def _hr
          l = BOX[:hrl]
          r = BOX[:hrr]
          m = "".ljust(@width - l.length - r.length, BOX[:hr])
          @separator_padding.times { _line }
          @window.send(@border_color, "#{l}#{m}#{r}")
          _nl
        end

        def _line parts = []
          return _hr if parts == :hr
          l = BOX[:l]
          r = BOX[:r]
          p = "".ljust(@border_padding, " ")

          @window.send(@border_color, "#{l}#{p}")
          parts.each do |str, color|
            @window.send(color, str)
          end
          @window.send(@border_color, "".ljust(@width - l.length - r.length - (p.length * 2) - parts.map{|s, _| s.length }.sum, " "))
          @window.send(@border_color, "#{p}#{r}")
          _nl
        end

        def _tborder
          tl = BOX[:tl]
          tr = BOX[:tr]
          m = "".ljust(@width - tl.length - tr.length, BOX[:t])
          @window.send(@border_color, "#{tl}#{m}#{tr}")
          _nl
        end

        def _bborder
          bl = BOX[:bl]
          br = BOX[:br]
          m = "".ljust(@width - bl.length - br.length, BOX[:b])
          @window.send(@border_color, "#{bl}#{m}#{br}")
        end

        def render!
          @width = @lines.map{|c| c.is_a?(Array) ? c.map{|s, _| s.length }.sum : 0 }.compact.max + (@border_padding * 2) + BOX[:l].length + BOX[:r].length

          _tborder
          @border_padding.times { _line }
          @lines.each {|parts| _line(parts) }
          @border_padding.times { _line }
          _bborder
        end
      end
    end
  end
end

