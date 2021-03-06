module DbSucker
  class Application
    module Dispatch
      def dispatch action = (@opts[:dispatch] || :help)
        if respond_to?("dispatch_#{action}")
          has_action = true
          fire(:dispatch_before, action)
          send("dispatch_#{action}")
        else
          fire(:dispatch_before, false)
          abort("unknown action `#{action}'\nRegistered actions: #{available_actions.join(", ")}")
        end
      rescue StandardError => ex
        fire(:dispatch_after, has_action ? action : false, ex)
        raise ex
      else
        fire(:dispatch_after, has_action ? action : false)
      end

      def available_actions
        methods.select{|m| m.to_s.start_with?("dispatch_") }.map{|s| s.to_s.gsub(/\Adispatch_/, "").to_sym }
      end

      def configful_dispatch identifier, variation, &block
        log "Using config directory #{c core_cfg_path.to_s, :magenta}"

        all_cfgs = cfg.yml_configs(true)
        enabled  = cfg.yml_configs(false)
        disabled = all_cfgs - enabled
        r = c("Found #{c all_cfgs.count, :blue} #{c "config files"}")
        r << c(" (#{c "#{disabled.count} disabled", :red}#{c ")"}") if disabled.any?
        log r << c("...")

        cfg.load_all_configs
        ctn = cfg.get(identifier)

        if identifier.present? && !ctn
          abort "Identifier `#{identifier}' couldn't be found!", 1
        end

        if ctn && variation && !(var = ctn.variation(variation))
          abort "Variation `#{variation}' for identifier `#{identifier}' couldn't be found!", 1
        end

        begin
          ctn.try(:ssh_begin)
          block.call(identifier, ctn, variation, var)
        ensure
          ctn.try(:ssh_end)
        end
      end

      # ----------------------------------------------------------------------

      # ====================
      # = Dev/Test actions =
      # ====================

      # via -a/--action cloop
      def dispatch_cloop
        begin
          trap_signals
          @sklaventreiber = SklavenTreiber.new(self, uniqid)
          @sklaventreiber.spooled do
            @opts[:stdout].disable
            hook(:prompt_start) { @opts[:stdout].enable }
            hook(:prompt_stop) { @opts[:stdout].disable(true) }
            begin
              @sklaventreiber._init_window
              loop do
                break if $core_runtime_exiting
                sleep 0.1
              end
            ensure
              sandboxed { @sklaventreiber.window.try(:stop) }
            end
          end
        ensure
          release_signals
        end
      end

      # via -a/--action console
      def dispatch_console
        configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
          begin ; require "pry" ; rescue LoadError ; end
          ::Kernel.binding.pry
        end
      end

      # via -a/--action threadtest
      def dispatch_threadtest
        t = Thread.new { Thread.stop }
        i, m = 1, [0, nil, nil]
        while i < 3
          m[0] += i == 1 ? -1 : 1
          t.priority = m[0]
          if t.priority != m[0]
            m[i] = t.priority
            m[0] = 0
            i += 1
          end
        end
        t.kill.join
        puts "Thread priority: -#{m[1].abs}..+#{m[2].abs}"
      end

      # via -a/--action sshdiag
      def dispatch_sshdiag
        _identifier, _ctn = false, false, false
        idstr = ARGV.shift
        varstr = ARGV.shift

        configful_dispatch(idstr, varstr) do |identifier, ctn, variation, var|
          unless ctn
            abort "This test requires a config identifier with an SSH connection!"
          end

          log c("\nPlease wait while we run some tests...\n", :blue)
          _identifier = identifier
          _ctn = ctn
          channels = []
          monitor = Monitor.new
          stop = false
          maxsessions = :unknown
          begin
            t = Thread.new {
              begin
                loop do
                  ctn.loop_ssh(0.1) { monitor.synchronize { channels.any? } }
                end
              rescue DbSucker::Application::Container::SSH::ChannelOpenFailedError
                monitor.synchronize do
                  maxsessions = channels.length - channels.select{|c| c[:open_failed] }.length
                  stop = true
                  print "!"
                end
                retry
              end
            }
            250.times do
              break if monitor.synchronize { stop }
              c, r = ctn.blocking_channel_result("sleep 900", blocking: false, channel: true, use_sh: true)
              monitor.synchronize do
                channels << c
                print "+"
              end
              sleep 0.1
            end
          ensure
            debug "Stopping sessions (#{channels.length})..."
            puts # newline for style
            i = 1
            loop do
              break if monitor.synchronize { channels.empty? }
              c = monitor.synchronize { channels.shift }
              debug "Channel ##{i} #{c[:pid] ? "with PID #{c[:pid]}" : "has no PID"}"
              ctn.kill_remote_process(c[:pid]) if c[:pid]
              print "-"
              i += 1
            end
            maxsessions = "#{maxsessions}+" if maxsessions.to_i >= 250
            log c("\n\nSSH MaxSessions: #{c maxsessions, :magenta}", :cyan)
            log "This value determines how many sessions we can multiplex over a single TCP connection."
            log "Currently, DbSucker can only utilize one connection, thus this value defines the maxmium concurrency."
            log "If you get errors you can either"
            log "  * increase the SSHd `MaxSessions' setting on the remote (if you can)"
            log "  * reduce the amount of workers and/or remote slots"
            log "  * fix the mess that is this tool, visit #{c "https://github.com/2called-chaos/db_sucker", :blue}"
            t.kill.join
          end
        end
      rescue Net::SSH::AuthenticationFailed => ex
        notify_exception(ex)
        log "\nDbSucker can't authenticate with the remote host, see exception."
        log "  * username correct?"
        log "  * password/keyfile correct?"
        log "  * check remote /var/log/auth.log?"
      rescue SocketError => ex
        notify_exception(ex)
        log "\nDbSucker can't establish a connection to the remote host " << c(cfg.get(idstr).source["ssh"]["hostname"], :magenta)
        log "  * typo in hostname / IP?"
        log "  * firewall?"
      end


      # ================
      # = Main actions =
      # ================

      # via -h/--help
      def dispatch_help
        colorized_help = @optparse.to_s.split("\n").map do |l|
          if l.start_with?("Usage:")
            lc = l.split(" ")
            "#{c lc[0]} #{c lc[1], :blue} #{c lc[2..-1].join(" "), :cyan}"
          elsif l.start_with?("#")
            c(l, :blue)
          elsif l.strip.start_with?("-")
            "#{c l.to_s[0...33], :cyan}#{c l[33..-1]}"
          else
            c(l)
          end
        end
        puts nil, colorized_help, nil
        puts c("The current config directory is #{c core_cfg_path.to_s, :magenta}"), nil
      end

      # via -v/--version
      def dispatch_info
        your_version = Gem::Version.new(DbSucker::VERSION)
        puts c ""
        puts c("     Your version: ", :blue) << c("#{your_version}", :magenta)

        print c("  Current version: ", :blue)
        if @opts[:check_for_updates]
          require "net/http"
          print c("checking...", :blue)

          begin
            current_version = Gem::Version.new Net::HTTP.get_response(URI.parse(DbSucker::UPDATE_URL)).body.strip

            if current_version > your_version
              status = c("#{current_version} (consider update)", :red)
            elsif current_version < your_version
              status = c("#{current_version} (ahead, beta)", :green)
            else
              status = c("#{current_version} (up2date)", :green)
            end
          rescue
            status = c("failed (#{$!.message})", :red)
          end

          print "#{"\b" * 11}#{" " * 11}#{"\b" * 11}" # reset line
          puts status
        else
          puts c("check disabled", :red)
        end

        # more info
        puts c ""
        puts c "  DbSucker is brought to you by #{c "bmonkeys.net", :green}"
        puts c "  Contribute @ #{c "github.com/2called-chaos/db_sucker", :cyan}"
        puts c "  Eat bananas every day!"
        puts c ""
      end

      # via --generate
      def dispatch_generate_config
        cfg_name = @opts[:config_name] || "default"
        cfg_file = "#{core_cfg_path}/#{cfg_name}.yml"
        puts c("Generating container configuration file `#{cfg_name}'")
        if File.exist?(cfg_file)
          abort "Conflict, file already exists: #{cfg_file}", 1
        else
          puts c("Writing #{cfg_file}", :green)
          FileUtils.mkdir_p(core_cfg_path)
          FileUtils.cp("#{ROOT}/doc/container_example.yml", cfg_file)
          editor = ENV["EDITOR"].presence
          exec("#{editor.chomp} #{cfg_file}") if editor
        end
      end

      # helper for #dispatch_stat_tmp
      def _dispatch_stat_tmp_display files, directories, managed, cleanup = false, sftp = false
        log "Directories: #{c directories.count, :blue}"
        log "      Files: #{c files.count, :blue} #{c "("}#{c managed.count, :blue}#{c " managed)"}"
        log "       Size: #{c human_bytes(files.map(&:second).sum), :blue} #{c "("}#{c human_bytes(managed.map(&:second).sum), :blue} #{c "managed)"}"

        if cleanup
          if managed.any?
            log c("WE ONLY SIMULATE! Nothing will be deleted!", :green) if opts[:simulate]
            warning "----------- Removing #{managed.count} managed files! Press Ctrl-C to abort -----------"
            managed.each{|f, s| warning "  REMOVE #{c "#{f}", :magenta} #{c human_bytes(s), :cyan}" }
            warning "----------- Removing #{managed.count} managed files! Press Ctrl-C to abort -----------"
            sleep 3
            4.times {|n| log "Cleaning up in #{3 - n}..." ; sleep 1 ; rll }

            managed.each do |f, s|
              if opts[:simulate]
                warning "(simulate)   Removing #{f}..."
              else
                warning "Removing #{f}..."
                sftp ? sftp.remove!(f) : File.unlink(f)
              end
            end
          else
            log c("No managed files found, nothing to cleanup.", :green)
          end
        end
      end

      # via --stat-tmp
      def dispatch_stat_tmp cleanup = false
        configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
          if ctn
            ctn.sftp_begin do |sftp|
              log c("Analyzing ") << c("remote", :cyan) << c(" temp directory #{c ctn.tmp_path, :magenta}")
              begin
                files = sftp.dir.glob("#{ctn.tmp_path}", "**/*")
              rescue Net::SFTP::StatusException => ex
                if ex.message["no such file"]
                  abort "Destination directory `#{ctn.tmp_path}' does not exist on the remote side!"
                else
                  raise
                end
              end

              d_files = files.select(&:file?).map{|f| ["#{ctn.tmp_path}/#{f.name}", f.attributes.size] }
              d_directories = files.select(&:directory?).map{|f| ["#{ctn.tmp_path}/#{f.name}"] }
              d_managed = files.select(&:file?).select{|f| f.name.end_with?(".dbsc", ".dbsc.tmp", ".dbsc.gz") }.map{|f| ["#{ctn.tmp_path}/#{f.name}", f.attributes.size] }
              _dispatch_stat_tmp_display(d_files, d_directories, d_managed, cleanup, sftp)
            end
          else
            log c("Analyzing ") << c("local", :cyan) << c(" temp directory #{c core_tmp_path, :magenta}")
            files = Dir.glob("#{core_tmp_path}/**/*")

            managed_files = files
            d_files = files.select{|f| File.file?(f) }.map{|f| [f, File.size(f)] }
            d_directories = files.select{|f| File.directory?(f) }
            d_managed = files.select{|f| File.file?(f) && File.basename(f).end_with?(".dbsc", ".dbsc.tmp", ".dbsc.gz") }.map{|f| [f, File.size(f)] }
            _dispatch_stat_tmp_display(d_files, d_directories, d_managed, cleanup)
          end
        end
      end

      # via --cleanup-tmp
      def dispatch_cleanup_tmp
        dispatch_stat_tmp(true)
      end

      # via -l/--list-databases
      def _list_databases identifier, ctn, variation, var
        return unless opts[:list_databases]
        log "Listing databases for identifier #{c identifier, :magenta}#{c "..."}"
        dbs = ctn.database_list(opts[:list_tables])
        print_db_table_list ctn.hostname, dbs
        throw :dispatch_handled
      end

      # via -t/--list-tables
      def _list_tables identifier, ctn, variation, var
        return if !(opts[:list_tables].present? && opts[:list_tables] != :all)
        print_db_table_list ctn.hostname, [[opts[:list_tables], ctn.table_list(opts[:list_tables])]]
        throw :dispatch_handled
      end

      # default action if variation given
      def _suck_variation identifier, ctn, variation, var
        if ctn && (var || (@opts[:suck_only].any? || @opts[:suck_except].any?))
          var ||= ctn.variation("default")
          begin
            trap_signals
            @sklaventreiber = SklavenTreiber.new(self, uniqid)
            @sklaventreiber.spooled do
              @sklaventreiber.whip_it!(ctn, var)
            end
          ensure
            release_signals
          end
          throw :dispatch_handled
        end
      end

      # default action if no variation is given
      def _default_listing identifier, ctn, variation, var
        db_table_listing(ctn ? [[identifier, ctn]] : cfg)
      end

      # default actions in order
      def dispatch_index
        configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
          catch :dispatch_handled do
            [:_list_databases, :_list_tables, :_suck_variation, :_default_listing].each do |meth|
              __send__(meth, identifier, ctn, variation, var)
            end
          end
        end
      end
    end
  end
end
