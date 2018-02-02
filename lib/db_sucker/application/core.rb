module DbSucker
  class Application
    module Core
      def sandboxed &block
        block.call
      rescue StandardError => ex
        e = ["#{ex.class}: #{ex.message}"]
        ex.backtrace.each{|l| e << "\t#{l}" }
        error(e.join("\n"))
        return false
      end

      def notify_exception label_or_ex, ex = nil
        error [].tap{|e|
          e << label_or_ex if ex
          e << "#{"\t" if ex}#{ex ? ex.class : label_or_ex.class}: #{ex ? ex.message : label_or_ex.message}"
          (ex ? ex : label_or_ex).backtrace.each{|l| e << "\t#{"  " if ex}#{l}" }
        }.join("\n")
      end

      def dump_file ctx, open = false, &block
        "#{core_tmp_path}/#{ctx}-#{Time.current.to_i}-#{uniqid}.log".tap do |df|
          FileUtils.mkdir_p(File.dirname(df))
          File.open(df, "wb", &block) if block
          if block && open && sdf = Shellwords.shellescape(df)
            fork { exec("#{opts[:core_dump_editor]} #{sdf} ; rm #{sdf}") }
          end
        end
      end

      def dump_core
        dump_file "coredump", true do |f|
          # thread info
          f.puts "#{Thread.list.length} threads:\n"
          Thread.list.each do |thr|
            f.puts "#{thr.inspect}"
            f.puts "      iType: #{thr == Thread.main ? :main_thread : thr[:itype] || :uncategorized}"
            f.puts "    Aborts?: #{thr.abort_on_exception}"
            f.puts "   Priority: #{thr.priority}"
            f.puts "     T-Vars: #{thr.thread_variables.inspect}"
            thr.thread_variables.each {|k| f.puts "             #{k} => #{thr.thread_variable(k)}" }
            f.puts "     F-Vars: #{thr.keys.inspect}"
            thr.keys.each {|k| f.puts "             #{k} => #{thr[k]}" }
            f.puts "  Backtrace: #{thr.backtrace.length}"
            thr.backtrace.each {|l| f.puts "             #{l}" }
            #f.puts "     Caller: #{thr.backtrace_locations.try(:length) || "unknown"}"
            #thr.backtrace_locations.each {|l| f.puts "             #{l}" } if thr.backtrace_locations
            f.puts
          end

          # worker info
          f.puts "\n\n#{sklaventreiber.workers.length} workers:\n"
          sklaventreiber.workers.each do |w|
            f.puts "#{"[SSH] " if w.sshing} #{w.descriptive} #{w.state}".strip
          end

          # slot pool
          f.puts "\n\n#{sklaventreiber.slot_pools.length} slot pools:\n"
          sklaventreiber.slot_pools.each do |name, pool|
            f.puts "#{name}: #{pool.slots}"
            pool.active.each do |thr|
              f.puts "\tactive\t #{thr} [#{thr[:itype]}]"
            end
            pool.waiting.each do |wthr, tthr|
              f.puts "\twaiting\t #{tthr} [#{tthr[:itype]}]"
            end
          end
        end
      end

      def sync &block
        @monitor.synchronize(&block)
      end

      def outsync &block
        @output_monitor.synchronize(&block)
      end

      def uniqid
        Digest::SHA1.hexdigest(SecureRandom.urlsafe_base64(128))
      end

      def spawn_thread type, &block
        waitlock = Queue.new
        sync do
          if !@opts[:"tp_#{type}"]
            warning "Thread type `#{type}' has no priority setting, defaulting to 0..."
          end

          # spawn thread
          Thread.new do
            waitlock.pop
            block.call(Thread.current)
          end.tap do |thr|
            # set type and priority
            thr[:itype] = type
            thr.priority = @opts[:"tp_#{type}"]
            thr.abort_on_exception = true

            # add signal methods
            signalify_thread(thr)

            # start thread
            waitlock << true
          end
        end
      end

      def signalify_thread thr
        # set lock and signal
        thr[:monitor] = Monitor.new
        thr[:signal] = thr[:monitor].new_cond

        # define helper methods
        def thr.signal
          self[:monitor].synchronize{ self[:signal].broadcast } ; self
        end
        def thr.wait(*a)
          self[:monitor].synchronize{ self[:signal].wait(*a) }
        end
        def thr.sync(&b)
          self[:monitor].synchronize(&b)
        end
      end

      def channelfy_thread thr
        def thr.active?
          alive?
        end

        def thr.closed?
          !alive?
        end

        def thr.closing?
          false
        end

        thr
      end

      def fake_channel &block
        FakeChannel.new(&block).tap do |ch|
          channelfy_thread(ch)
          signalify_thread(ch)
        end
      end

      def wakeup_handlers
        Thread.list.each{|thr| thr.try(:signal) }
      end


      # =================
      # = Configuration =
      # =================
      def core_cfg_path
        File.expand_path(ENV["DBS_CFGDIR"].presence || "~/.db_sucker")
      end

      def core_tmp_path
        "#{File.expand_path(ENV["DBS_TMPDIR"] || ENV["TMPDIR"] || "/tmp")}/db_sucker_temp"
      end

      def core_cfg_configfile
        "#{core_cfg_path}/config.rb"
      end

      def load_appconfig
        return unless File.exist?(core_cfg_configfile)
        eval File.read(core_cfg_configfile, encoding: "utf-8"), binding, core_cfg_configfile
      end


      # ===================
      # = Signal trapping =
      # ===================
      def trap_signals
        debug "Trapping INT signal..."
        Signal.trap("INT") do
          $core_runtime_exiting = 1
          Kernel.puts "Interrupting..."
        end
        Signal.trap("TERM") do
          $core_runtime_exiting = 2
          Kernel.puts "Terminating..."
        end
        Signal.trap("USR1") do
          dump_core
        end
      end

      def release_signals
        debug "Releasing INT signal..."
        Signal.trap("INT", "DEFAULT")
        Signal.trap("TERM", "DEFAULT")
        Signal.trap("USR1", "DEFAULT")
      end

      def haltpoint
        raise Interrupt if $core_runtime_exiting && !$core_runtime_graceful
      end


      # ==========
      # = Events =
      # ==========
      def hook *which, &hook_block
        which.each do |w|
          @hooks[w.to_sym] ||= []
          @hooks[w.to_sym] << hook_block
        end
      end

      def fire which, *args
        return if @disable_event_firing
        sync { debug "[Event] Firing #{which} (#{@hooks[which].try(:length) || 0} handlers) #{args.map(&:to_s)}", 99 }
        @hooks[which] && @hooks[which].each{|h| h.call(self, *args) }
      end
    end
  end
end
