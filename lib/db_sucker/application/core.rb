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
      # def error_logger
      #   sync do
      #     @error_logger ||= begin
      #       FileUtils.mkdir_p(File.dirname(core_logfile_errors))
      #       Logger.new(core_logfile_errors, @opts[:log_keep], @opts[:log_size])
      #     end
      #   end
      # end

      # def dev_logger
      #   sync do
      #     @dev_logger ||= begin
      #       FileUtils.mkdir_p(File.dirname(core_logfile_dev))
      #       Logger.new(core_logfile_dev, @opts[:log_keep], @opts[:log_size])
      #     end
      #   end
      # end

      # def ban_logger
      #   sync do
      #     @ban_logger ||= begin
      #       FileUtils.mkdir_p(File.dirname(core_logfile_bans))
      #       Logger.new(core_logfile_bans, @opts[:log_keep], @opts[:log_size])
      #     end
      #   end
      # end

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
        @hooks[which] && @hooks[which].each{|h| h.call(*args) }
      end
    end
  end
end
