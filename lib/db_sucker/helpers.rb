module DbSucker
  module Helpers
    BYTE_UNITS = %W(TiB GiB MiB KiB B).freeze

    def human_filesize(s)
      s = s.to_f
      i = BYTE_UNITS.length - 1
      while s > 512 && i > 0
        i -= 1
        s /= 1024
      end
      ((s > 9 || s.modulo(1) < 0.1 ? '%d' : '%.1f') % s) + ' ' + BYTE_UNITS[i]
    end

    def human_seconds(secs)
      secs = secs.to_i
      t_minute = 60
      t_hour = t_minute * 60
      t_day = t_hour * 24
      t_week = t_day * 7
      "".tap do |r|
        if secs >= t_week
          r << "#{secs / t_week}w "
          secs = secs % t_week
        end

        if secs >= t_day || !r.blank?
          r << "#{secs / t_day}d "
          secs = secs % t_day
        end

        if secs >= t_hour || !r.blank?
          r << "#{secs / t_hour}h "
          secs = secs % t_hour
        end

        if secs >= t_minute || !r.blank?
          r << "#{secs / t_minute}m "
          secs = secs % t_minute
        end

        r << "#{secs}s" unless r.include?("d")
      end.strip
    end

    # def human_number(n)
    #   n.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
    # end

    # def ask question
    #   logger.log_with_print(false) do
    #     log c("#{question} ", :blue)
    #     STDOUT.flush
    #     STDIN.gets.chomp
    #   end
    # end

    def uncolorize str
      str.gsub(/\033\[[0-9;]+m/, '')
    end

    def render_table table, headers = []
      [].tap do |r|
        col_sizes = table.map{|col| col.map{|i| uncolorize(i.to_s) }.map(&:length).max }
        headers.map{|i| uncolorize(i.to_s) }.map(&:length).each_with_index do |length, header|
          col_sizes[header] = [col_sizes[header] || 0, length || 0].max
        end

        # header
        if headers.any?
          r << [].tap do |line|
            col_sizes.count.times do |col|
              line << headers[col].ljust(col_sizes[col] + (headers[col].length - uncolorize(headers[col]).length))
            end
          end.join(" | ")
          r << "".ljust(col_sizes.inject(&:+) + ((col_sizes.count - 1) * 3), "-")
        end

        # records
        table[0].count.times do |row|
          r << [].tap do |line|
            col_sizes.count.times do |col|
              line << "#{table[col][row]}".ljust(col_sizes[col] + (table[col][row].to_s.length - uncolorize(table[col][row]).length))
            end
          end.join(" | ")
        end
      end
    end

    def print_db_table_list host, dbs
      if dbs[0] && dbs[0].is_a?(Array)
        log ""
        log c(host, :red)
      end

      dbs.each_with_index do |db, i|
        if db.is_a?(Array)
          d = c db[0], :magenta
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

    def uniqid
      Digest::SHA1.hexdigest(SecureRandom.urlsafe_base64(128))
    end

    def rll
      print "\033[A"
      print "\033[2K\r"
    end

    def render_progress_table all_workers, workers, active_workers, clear_table = false
      if clear_table && $last_tc
        ($last_tc).times{ rll }
      end

      # display progress table
      table = [[], []]
      active_workers.each do |w|
        table[0] << c(w.table, :magenta)
        table[1] << c(*w.colored_status)
      end
      w_done = all_workers.count - workers.count - active_workers.select(&:active?).count
      t = render_table(table, [c("table", :cyan), c("status (#{f_percentage w_done, all_workers.count} – #{w_done}/#{all_workers.count} workers done)", :cyan)])
      $last_tc = t.count
      t.each{|l| log("#{l}") }
    end

    def trap_signals
      debug "Trapping INT signal..."
      Signal.trap("INT") {|sig| Thread.main[:shutdown] = Signal.signame(sig) }
    end

    def release_signals reraise = false
      debug "Releasing INT signal trap..."
      Signal.trap("INT", "DEFAULT")
      was = Thread.main[:shutdown]
      Thread.main[:shutdown] = nil
      if reraise && was
        raise Interrupt
      end
      true
    end

    def f_percentage part, total
      ('%.2f' % ((part.to_d / total.to_d) * 100)) << '%'
    end
  end
end
