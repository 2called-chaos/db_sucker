module DbSucker
  class Application
    module Core
      def sandboxed logger = nil, &block
        block.call
      rescue StandardError => ex
        logger ||= error_logger
        logger.error("#{ex.class}: #{ex.message}")
        ex.backtrace.each{|l| logger.error("\t#{l}") }
      end

      def sync &block
        @monitor.synchronize(&block)
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
          $core_runtime_exiting = true
          Kernel.puts "Interrupting..."
        end
        Signal.trap("TERM") do
          $core_runtime_exiting = true
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

      # ===================
      # = Window (curses) =
      # ===================
      def start_window
        @window = Window.new(self).tap{|w| w.init! }
      end

      def close_window
        @window.try(:close)
      end
    end
  end
end
