# Add event listeners to inject some debug information.
# This is for developing or debugging.

module DbSucker
  module Patches
    class Developer < Application::Tie
      def self.hook!(app)
        app.hook :core_shutdown do
          app.debug "RSS: #{app.human_bytes(`ps h -p #{Process.pid} -o rss`.strip.split("\n").last.to_i * 1024)}"
        end

        app.hook :worker_routine_before do |_, routine|
          app.debug "RSS-before-#{routine}: #{app.human_bytes(`ps h -p #{Process.pid} -o rss`.strip.split("\n").last.to_i * 1024)}"
        end

        app.hook :worker_routine_after do |_, routine|
          app.debug "RSS-after-#{routine}: #{app.human_bytes(`ps h -p #{Process.pid} -o rss`.strip.split("\n").last.to_i * 1024)}"
        end
      end
    end
  end
end