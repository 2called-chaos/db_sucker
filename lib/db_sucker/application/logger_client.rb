module DbSucker
  class Application
    module LoggerClient
      extend ActiveSupport::Concern

      included do
        [:log, :warn, :abort, :debug].each do |meth|
          define_method meth, ->(*a, &b) { Thread.main.app_logger.send(meth, *a, &b) }
        end
      end

      def logger
        Thread.main.app_logger
      end

      # Shortcut for logger.colorize
      def c str, color = :yellow
        logger.colorize? ? logger.colorize(str, color) : str
      end
    end
  end
end
