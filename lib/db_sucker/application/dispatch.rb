# Encoding: Utf-8
module DbSucker
  class Application
    module Dispatch
      def dispatch action = (@opts[:dispatch] || :help)
        case action
          when :version, :info then dispatch_info
          else
            if respond_to?("dispatch_#{action}")
              send("dispatch_#{action}")
            else
              abort("unknown action #{action}", 1)
            end
        end
      end

      def dispatch_help
        logger.log_without_timestr do
          log ""
          @optparse.to_s.split("\n").each(&method(:log))
          log ""
          log "The current config directory is #{c config_dir.to_s, :magenta}\n"
        end
      end

      def dispatch_info
        logger.log_without_timestr do
          log ""
          log "     Your version: #{your_version = Gem::Version.new(DbSucker::VERSION)}"

          # get current version
          logger.log_with_print do
            log "  Current version: "
            if @opts[:check_for_updates]
              require "net/http"
              log c("checking...", :blue)

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

              logger.raw "#{"\b" * 11}#{" " * 11}#{"\b" * 11}", :print # reset cursor
              log status
            else
              log c("check disabled", :red)
            end
          end
          log ""
          log "  The current config directory is #{c config_dir.to_s, :magenta}"

          # more info
          log ""
          log "  DBSucker is brought to you by #{c "bmonkeys.net", :green}"
          log "  Contribute @ #{c "github.com/2called-chaos/db_sucker", :cyan}"
          log "  Eat bananas every day!"
          log ""
        end
      end

      def configful_dispatch identifier, variation, &block
        log "Using config directory #{c config_dir.to_s, :magenta}"
        log "Found #{c config_files.count, :blue} #{c "config files"}#{c "..."}"
        load_all_configs

        if identifier.present?
          if ctn = cfg.get(identifier)
            ctn.ssh_begin
          else
            abort "Identifier `#{identifier}' couldn't be found!", 1
          end
        end

        if ctn && variation && !(var = ctn.variation(variation))
          abort "Variation `#{variation}' for identifier `#{identifier}' couldn't be found!", 1
        end

        block.call(identifier, ctn, variation, var)
      ensure
        ctn.try(:ssh_end)
      end

      def dispatch_stat_tmp cleanup = false
        configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
          if ctn
            ctn.sftp_start do |sftp|
              log c "Analyzing temp directory #{c ctn.tmp_path, :magenta}", :green
              begin
                files = sftp.dir.glob("#{ctn.tmp_path}", "**/*")
              rescue Net::SFTP::StatusException => ex
                if ex.message["no such file"]
                  logger.warn "Destination directory `#{ctn.tmp_path}' does not exist on the remote side!"
                else
                  raise
                end
              end

              managed_files = files.select(&:file?).select{|f| f.name.end_with?(".dbsc", ".dbsc.tmp", ".dbsc.gz") }

              log "Directories: #{c files.select(&:directory?).count, :blue}"
              log "      Files: #{c files.select(&:file?).count, :blue} #{c "("}#{c managed_files.count, :blue}#{c " managed)"}"
              log "       Size: #{c human_filesize(files.map{|f| f.attributes.size }.sum), :blue} #{c "("}#{c human_filesize(managed_files.map{|f| f.attributes.size }.sum), :blue} #{c "managed)"}"

              if cleanup
                if managed_files.any?
                  log c("WE ONLY SIMULATE! Nothing will be deleted!", :green) if opts[:simulate]
                  logger.warn "----------- Removing #{managed_files.count} managed files! Press Ctrl-C to abort -----------"
                  managed_files.each{|f| logger.warn "  REMOVE #{c "#{ctn.tmp_path}/#{f.name}", :magenta} #{c human_filesize(f.attributes.size), :cyan}" }
                  logger.warn "----------- Removing #{managed_files.count} managed files! Press Ctrl-C to abort -----------"
                  sleep 3
                  4.times {|n| log "Cleaning up in #{3 - n}..." ; sleep 1 ; rll }

                  managed_files.each do |f|
                    fpath = "#{ctn.tmp_path}/#{f.name}"

                    if opts[:simulate]
                      logger.warn "(simulate)   Removing #{fpath}..."
                    else
                      logger.warn "Removing #{fpath}..."
                      sftp.remove!(fpath)
                    end
                  end
                else
                  log c("No managed files found, nothing to cleanup.", :green)
                end
              end
            end
          else
            tpath = "#{File.expand_path(ENV["DBS_TMPDIR"] || ENV["TMPDIR"] || "/tmp")}/db_sucker_tmp"
            log c "Analyzing local temp directory #{c tpath, :magenta}", :green
            begin
              files = Dir.glob("#{tpath}/**/*")
            rescue Net::SFTP::StatusException => ex
              if ex.message["no such file"]
                logger.warn "Destination directory `#{ctn.tmp_path}' does not exist on the remote side!"
              else
                raise
              end
            end

            managed_files = files.select{|f| File.file?(f) && File.basename(f).end_with?(".dbsc", ".dbsc.tmp", ".dbsc.gz") }

            log "Directories: #{c files.select{|f| File.directory?(f)}.count, :blue}"
            log "      Files: #{c files.select{|f| File.file?(f)}.count, :blue} #{c "("}#{c managed_files.count, :blue}#{c " managed)"}"
            log "       Size: #{c human_filesize(files.map{|f| File.size(f) }.sum), :blue} #{c "("}#{c human_filesize(managed_files.map{|f| File.size(f) }.sum), :blue} #{c "managed)"}"

            if cleanup
              if managed_files.any?
                log c("WE ONLY SIMULATE! Nothing will be deleted!", :green) if opts[:simulate]
                logger.warn "----------- Removing #{managed_files.count} managed files! Press Ctrl-C to abort -----------"
                managed_files.each{|f| logger.warn "  REMOVE #{c "#{f}", :magenta} #{c human_filesize(File.size(f)), :cyan}" }
                logger.warn "----------- Removing #{managed_files.count} managed files! Press Ctrl-C to abort -----------"
                sleep 3
                4.times {|n| log "Cleaning up in #{3 - n}..." ; sleep 1 ; rll }

                managed_files.each do |f|
                  if opts[:simulate]
                    logger.warn "(simulate)   Removing #{f}..."
                  else
                    logger.warn "Removing #{f}..."
                    File.unlink(f)
                  end
                end
              else
                log c("No managed files found, nothing to cleanup.", :green)
              end
            end
          end
        end
      end

      def dispatch_cleanup_tmp
        dispatch_stat_tmp(true)
      end

      def dispatch_index
        configful_dispatch(ARGV.shift, ARGV.shift) do |identifier, ctn, variation, var|
          # ============
          # = List DBs =
          # ============
          if opts[:list_databases]
            log "Listing databases for identifier #{c identifier, :magenta}#{c "..."}"
            dbs = ctn.mysql_database_list(opts[:list_tables])

            print_db_table_list(ctn.mysql_hostname, dbs)
            return
          end

          # ===============
          # = List tables =
          # ===============
          if opts[:list_tables].present? && opts[:list_tables] != :all
            print_db_table_list ctn.mysql_hostname, [[opts[:list_tables], ctn.mysql_table_list(opts[:list_tables])]]
            return
          end

          # ==================
          # = Suck variation =
          # ==================
          if ctn && var
            id = uniqid
            trap_signals
            ttt = var.tables_to_transfer
            log "Transfering #{c ttt.count, :blue} #{c "tables from DB"} #{c ctn.data["source"]["database"], :magenta}#{c "..."}"
            log "Transaction ID is #{c id, :blue}"

            if ctn.tmp_path.present?
              ctn.sftp_begin
              begin
                ctn.sftp_start do |sftp|
                  # check tmp directory
                  debug "Checking remote temp directory #{c ctn.tmp_path, :magenta}"
                  begin
                    sftp.dir.glob("#{ctn.tmp_path}", "**/*")
                  rescue Net::SFTP::StatusException => ex
                    if ex.message["no such file"]
                      abort "Destination directory `#{ctn.tmp_path}' does not exist on the remote side!", 2
                    else
                      raise
                    end
                  end
                end

                # starting workers
                workers = []
                ttt.each do |tab|
                  debug "Starting worker for table `#{tab}' (#{id})..."
                  workers << Configuration::Worker.new(self, id, ctn, var, tab)
                end

                # progess display
                log ""
                sleep 0.1
                first_iteration = true
                active_workers = []
                all_workers = workers.dup
                display = Thread.new do
                  while workers.any? || active_workers.any?(&:active?)
                    # activate workers
                    active_workers = active_workers.select(&:active?) if ttt.length > 20
                    while active_workers.select(&:active?).count < 20 && workers.any?
                      w = workers.shift
                      w.start
                      active_workers << w
                    end

                    # create deferred workers
                    $deferred_import.synchronize do
                      while $deferred_import.any?
                        w = Configuration::Worker.new(self, *$deferred_import.shift)
                        workers << w
                        all_workers << w
                      end
                    end

                    # render table
                    render_progress_table(all_workers, workers, active_workers, !first_iteration)
                    first_iteration = false
                    sleep 0.5
                  end
                end

                # poll ssh
                poll = Thread.new do
                  ctn.loop_ssh(0.1) { workers.any? || active_workers.any?(&:active?) }
                end

                display.join
                poll.join

                # finish up
                render_progress_table(all_workers, workers, all_workers, true)
                log ""
                log c("All done", :green) unless Thread.main[:shutdown]
              ensure
                ctn.sftp_end
              end
            else
              abort "Transfering streams is not yet implemented :( Please define a tmp_location in your source config.", 1
            end

            release_signals(true)
            return
          end

          # default listing
          db_table_listing(ctn ? [[identifier, ctn]] : cfg)
        end
      end
    end
  end
end
