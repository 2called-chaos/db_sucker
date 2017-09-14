# Monkeypatch™ Thread class to count threads being created.
# This is for developing but you can see the amount if debug is enabled.

module DbSucker
  module Patches
    class ThreadCounter < Application::Tie
      def self.hook!(app)
        $thread_count = 0
        $thread_count_monitor = Monitor.new

        ::Thread.class_eval do
          class << self
            def new_with_counter *a, &b
              $thread_count_monitor.synchronize { $thread_count += 1 }
              new_without_counter(*a, &b)
            end
            alias_method :new_without_counter, :new
            alias_method :new, :new_with_counter
          end
        end

        app.hook :core_shutdown do
          app.debug "#{$thread_count} threads spawned"
        end
      end
    end
  end
end

# [DEBUG] 13 threads spawned
