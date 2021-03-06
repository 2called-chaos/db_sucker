module DbSucker
  class Application
    module OutputHelper
      def self.hook ctx
        [:puts, :print, :warn, :debug, :log, :warning, :error, :abort, :decolorize, :db_table_listing, :print_db_table_list, :decolorize, :render_table, :f_percentage, :human_bytes, :human_number, :human_percentage, :human_seconds, :human_seconds2, :rll, :c, :strbool].each do |meth|
          ctx.__send__(:define_method, meth) do |*a|
            Thread.main[:app].__send__(meth, *a)
          end
        end
      end

      def puts *a
        outsync { @opts[:stdout].send(:puts, *a) }
      end

      def print *a
        outsync { @opts[:stdout].send(:print, *a) }
      end

      def warn *a
        outsync { @opts[:stdout].send(:warn, *a) }
      end

      def debug msg, lvl = 1
        puts c("[DEBUG] #{msg}", :black) if @opts[:debug] && @opts[:debug] >= lvl
      end

      def log msg
        puts c("#{msg}")
      end

      def warning msg
        warn c("[WARN] #{msg}", :red)
      end

      def error msg
        warn c("[ERROR] #{msg}", :red)
      end

      def abort msg, exit_code = 1
        warn c("[ABORT] #{msg}", :red)
        exit(exit_code) if exit_code
      end

      def rll
        print "\033[A"
        print "\033[2K\r"
      end

      def render_table table, headers = []
        [].tap do |r|
          col_sizes = table.map{|col| col.map{|i| decolorize(i.to_s) }.map(&:length).max }
          headers.map{|i| decolorize(i.to_s) }.map(&:length).each_with_index do |length, header|
            col_sizes[header] = [col_sizes[header] || 0, length || 0].max
          end

          # header
          if headers.any?
            r << [].tap do |line|
              col_sizes.count.times do |col|
                line << headers[col].ljust(col_sizes[col] + (headers[col].length - decolorize(headers[col]).length))
              end
            end.join(" | ")
            r << "".ljust(col_sizes.inject(&:+) + ((col_sizes.count - 1) * 3), "-")
          end

          # records
          table[0].count.times do |row|
            r << [].tap do |line|
              col_sizes.count.times do |col|
                line << "#{table[col][row]}".ljust(col_sizes[col] + (table[col][row].to_s.length - decolorize(table[col][row]).length))
              end
            end.join(" | ")
          end
        end
      end

      def db_table_listing col
        col.each do |id, ccfg|
          log ""
          log "====================="
          log "=== #{c id, :magenta}"
          log "====================="
          a, b = [], []
          ccfg.variations.map do |name, vd|
            a << c(name, :blue)
            b << (vd.label.present? ? c(vd.label) : c("no label", :black))
          end
          render_table([a, b], [c("variation"), c("label")]).each{|l| log("#{l}") }
        end
      end

      def print_db_table_list host, dbs
        log ""
        log c(host, :red)

        dbs.each_with_index do |db, i|
          if db.is_a?(Array)
            d = c(db[0], :magenta) << c(" (#{db[1].length})", :black)
            if i == dbs.count - 1
              log("#{db[1].any? ? "├──" : "└──"} #{d}")
            else
              log("├── #{d}")
            end

            table = render_table([db[1].map{|r| c(r[1], :cyan) }, db[1].map{|r| c(r[0], :green) }])
            table.each_with_index do |l, i2|
              if i2 == table.count - 1
                log("│   └── #{l}")
              else
                log("│   ├── #{l}")
              end
            end
          else
            log "  #{c db, :blue}"
          end
        end
      end

      def strbool v
        v = true if ["true", "t", "1", "y", "yes", "on"].include?(v)
        v = false if ["false", "f", "0", "n", "no", "off"].include?(v)
        v
      end

      def f_percentage have, total, nn = 2
        human_percentage(total == 0 ? 100 : have == 0 ? 0 : (have.to_d / total.to_d * 100.to_d), nn)
      end

      def human_bytes bytes
        return false unless bytes
        {
          'B'  => 1024,
          'KB' => 1024 * 1024,
          'MB' => 1024 * 1024 * 1024,
          'GB' => 1024 * 1024 * 1024 * 1024,
          'TB' => 1024 * 1024 * 1024 * 1024 * 1024
        }.each_pair { |e, s| return "#{"%.2f" % (bytes.to_d / (s / 1024)).round(2)} #{e}" if bytes < s }
      end

      def human_number(n)
        n.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
      end

      def human_percentage(n, nn = 2)
        "%.#{nn}f%%" % n
      end

      def human_seconds secs, sprec = 0
        t_minute = 60
        t_hour = t_minute * 60
        t_day = t_hour * 24
        t_week = t_day * 7
        t_month = t_day * 30
        t_year = t_month * 12
        "".tap do |r|
          if secs >= t_year
            r << "#{"%i" % (secs / t_year)}y "
            secs = secs % t_year
          end

          if secs >= t_month
            r << "#{"%i" % (secs / t_month)}m "
            secs = secs % t_month
          end

          if secs >= t_week
            r << "#{"%i" % (secs / t_week)}w "
            secs = secs % t_week
          end

          if secs >= t_day || !r.blank?
            r << "#{"%i" % (secs / t_day)}d "
            secs = secs % t_day
          end

          if secs >= t_hour || !r.blank?
            r << "#{"%i" % (secs / t_hour)}h "
            secs = secs % t_hour
          end

          if secs >= t_minute || !r.blank?
            r << "#{"%i" % (secs / t_minute)}m "
            secs = secs % t_minute
          end

          r << "#{"%.#{sprec}f" % secs.round(sprec)}s" unless r.include?("d")
        end.strip
      end

      def human_seconds2 secs
        return "?:¿?:¿?" if secs.try(:infinite?)
        Time.at(secs.round).utc.strftime("%k:%M:%S").strip
      end
    end
  end
end
