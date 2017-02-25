module DbSucker
  class Application
    attr_reader :opts, :cfg
    # attr_reader :opts, :threads, :ea_queue, :ip_queue, :hooks, :stats, :window, :boot, :db, :backbuffer, :triggers, :assessors, :delayed_ip_queue, :delayed_ip_queue_monitor
    # attr_accessor :status
    # include Helper
    include Core
    include Colorize
    include OutputHelper
    # include Core
    # include Controls
    # include Database
    include Dispatch

    # =========
    # = Setup =
    # =========
    def self.dispatch *a
      new(*a) do |app|
        Thread.main[:app] = app
        app.load_appconfig
        app.parse_params
        begin
          app.dispatch
          app.haltpoint
        rescue Interrupt
          app.abort("Interrupted", 1)
        rescue StandardError => ex
          app.warn app.c("[FATAL] #{ex.class}: #{ex.message}", :red)
          ex.backtrace.each do |l|
            app.warn app.c("\t#{l}", :red)
          end
          app.fire(:core_exception, ex)
          app.abort "Unhandled exception terminated application!"
        ensure
          app.fire(:core_shutdown)
          app.debug "#{Thread.list.length} threads remain..."
          Thread.main[:app] = nil
        end
      end
    end

    def initialize env, argv
      @boot = Time.current
      @env, @argv = env, argv
      @hooks = {}
      @monitor = Monitor.new
      @cfg = ContainerCollection.new(self)
      @opts = {
        dispatch: :index,        # (internal) action to dispatch
        mode: :default,          # (internal) mode for action
        check_for_updates: true, # -z flag
        colorize: true,          # --monochrome flag
        debug: false,            # -d flag
        quiet: false,            # -q flag
        stdout: STDOUT,          # (internal) STDOUT redirect
        pipein: ARGF,            # (internal) INPUT redirect

        list_databases: false,   # --list-databases flag
        list_tables: false,      # --list-tables flag
        simulate: false,         # --simulate flag
        deferred_import: true,   # -n flag

        # log files
        log_keep: 10,                   # Amount of logfiles to keep
        log_size: 10240000,             # Max size of each logfile (in bytes)
      }
      init_params
      yield(self)
    end

    def init_params
      @optparse = OptionParser.new do |opts|
        opts.banner = "Usage: db_sucker [options] [identifier [variation]]"

        opts.separator("\n" << "# Application options")
        opts.on("-a", "--action ACTION", String, "Dispatch given action") {|v| @opts[:dispatch] = v }
        opts.on("-m", "--mode MODE", String, "Dispatch action with given mode") {|v| @opts[:mode] = v.to_sym }
        opts.on("-n", "--no-deffer", "Don't use deferred import for files > 50 MB SQL data size.") { @opts[:deferred_import] = false }
        opts.on("-l", "--list-databases", "List databases for given identifier.") { @opts[:list_databases] = true }
        opts.on("-t", "--list-tables [DATABASE]", String, "List tables for given identifier and database.", "If used with --list-databases the DATABASE parameter is optional.") {|s| @opts[:list_tables] = s || :all }
        opts.on(      "--stat-tmp", "Show information about the remote temporary directory.", "If no identifier is given check local temp directory instead.") { @opts[:dispatch] = :stat_tmp }
        opts.on(      "--cleanup-tmp", "Remove all temporary files from db_sucker in target directory.") { @opts[:dispatch] = :cleanup_tmp }
        opts.on(      "--simulate", "To use with --cleanup-tmp to not actually remove anything.") { @opts[:simulate] = true }

        opts.separator("\n" << "# General options")
        opts.on("-d", "--debug [lvl=1]", Integer, "Enable debug output") {|l| @opts[:debug] = l || 1 }
        opts.on("--monochrome", "Don't colorize output") { @opts[:colorize] = false }
        opts.on("-h", "--help", "Shows this help") { @opts[:dispatch] = :help }
        opts.on("-v", "--version", "Shows version and other info") { @opts[:dispatch] = :info }
        opts.on("-z", "Do not check for updates on GitHub (with -v/--version)") { @opts[:check_for_updates] = false }
      end
    end

    def parse_params
      @optparse.parse!(@argv)
    rescue OptionParser::ParseError => e
      abort(e.message)
      dispatch(:help)
      exit 1
    end



    # =================
    # = Configuration =
    # =================
    def core_cfg_path
      File.expand_path(ENV["DBS_CFGDIR"].presence || "~/.db_sucker")
    end

    def core_tmp_path
      File.expand_path(ENV["DBS_TMPDIR"] || ENV["TMPDIR"] || "/tmp")
    end

    def core_cfg_configfile
      "#{core_cfg_path}/config.rb"
    end

    def load_appconfig
      return unless File.exist?(core_cfg_configfile)
      eval File.read(core_cfg_configfile, encoding: "utf-8"), binding, core_cfg_configfile
    end
  end
end
