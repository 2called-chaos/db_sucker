# Create this file as ~/.db_sucker/config.rb
# This file is eval'd in the application object's context after it's initialized!

# Change option defaults (arguments will still override these settings)
# For options refer to application.rb#initialize
#     https://github.com/2called-chaos/db_sucker/blob/master/lib/db_sucker/application.rb

#opts[:consumers] = 20
#opts[:pv_enabled] = false


# Add event listeners, there are currently these events with their arguments:
#   - core_exception(app, exception)
#   - core_shutdown(app)
#   - worker_routine_before_all(app, worker)
#   - worker_routine_before(app, worker, current_routine)
#   - worker_routine_after(app, worker, current_routine)
#   - worker_routine_after_all(app, worker)
#   - prompt_start(app, prompt_label, prompt_options)

hook :core_shutdown do |app|
  puts "We're done! (event listener example in config.rb)"
end

# Define additional actions that can be invoked using `-a/--action foo`
def dispatch_foo
  configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
    # execute command on remote and print results
    puts ctn.blocking_channel_result("lsb_release -a").to_a
  end
end
