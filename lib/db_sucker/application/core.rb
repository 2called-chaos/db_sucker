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

      def sync &block
        @monitor.synchronize(&block)
      end

      def uniqid
        Digest::SHA1.hexdigest(SecureRandom.urlsafe_base64(128))
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
      end

      def release_signals
        debug "Releasing INT signal..."
        Signal.trap("INT", "DEFAULT")
        Signal.trap("TERM", "DEFAULT")
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
        sync { debug "[Event] Firing #{which} (#{@hooks[which].try(:length) || 0} handlers) #{args.map(&:class)}", 99 }
        @hooks[which] && @hooks[which].each{|h| h.call(self, *args) }
      end
    end
  end
end
