# Create this file as ~/.db_sucker/config.rb
# This file is eval'd in the application object's context after it's initialized!

# Change option defaults (arguments will still override these settings)
# For all options refer to application.rb#initialize
#     https://github.com/2called-chaos/db_sucker/blob/master/lib/db_sucker/application.rb

# These are default options, you can clear the whole file if you want.

opts[:debug] = false                    # --debug flag
opts[:colorize] = true                  # --monochrome flag
opts[:consumers] = 10                   # amount of workers to run at the same time
opts[:deferred_threshold] = 50_000_000  # 50 MB
opts[:status_format] = :full            # used for IO operations, can be one of: none, minimal, full
opts[:pv_enabled] = true                # disable pv utility autodiscovery (force non-usage)

# used to open core dumps (should be a blocking call, e.g. `subl -w' or `mate -w')
# MUST be windowed! vim, nano, etc. will not work!
opts[:core_dump_editor] = "subl -w"

# amount of workers that can use a slot (false = infinite)
opts[:slot_pools][:all] = false
opts[:slot_pools][:remote] = false
opts[:slot_pools][:download] = false
opts[:slot_pools][:local] = false
opts[:slot_pools][:import] = 3
opts[:slot_pools][:deferred] = 1


# Add event listeners, there are currently these events with their arguments:
#   - core_exception(app, exception)
#   - core_shutdown(app)
#   - worker_routine_before_all(app, worker)
#   - worker_routine_before(app, worker, current_routine)
#   - worker_routine_after(app, worker, current_routine)
#   - worker_routine_after_all(app, worker)
#   - prompt_start(app, prompt_label, prompt_options)
#   - prompt_stop(app, prompt_label)

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
