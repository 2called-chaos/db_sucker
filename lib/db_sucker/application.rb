module DbSucker
  # Logger Singleton
  MAIN_THREAD = ::Thread.main
  def MAIN_THREAD.app_logger
    MAIN_THREAD[:app_logger] ||= Banana::Logger.new.tap{|l| l.disable(:debug) }
  end

  class Application
    attr_reader :opts, :cfg
    include Dispatch
    include Helpers
    include LoggerClient

    # =========
    # = Setup =
    # =========
    def self.dispatch *a
      new(*a) do |app|
        app.parse_params
        app.logger
        begin
          app.dispatch
        rescue Interrupt
          app.abort("Interrupted", 1)
        end
      end
    end

    def initialize env, argv
      @env, @argv = env, argv
      @cfg = Configuration.new(self)
      @opts = {
        dispatch: :index,
        list_tables: false,
        list_databases: false,
        check_for_updates: true,
        debug: false,
        simulate: false,
        deferred_import: true,
      }
      $deferred_import = []
      $deferred_import.extend(MonitorMixin)
      $importing = []
      $importing.extend(MonitorMixin)
      $deferred_importer = Mutex.new
      yield(self)
    end

    def parse_params
      @optparse = OptionParser.new do |opts|
        opts.banner = "Usage: db_sucker [options] [identifier] [variation]"

        opts.separator(c "# Application options", :blue)
        opts.on("-n", "--no-deffer", "Don't use deferred import for files > 50 MB SQL data size.") { @opts[:deferred_import] = false }
        opts.on("-l", "--list-databases", "List databases for given identifier.") { @opts[:list_databases] = true }
        opts.on("-t", "--list-tables [DATABASE]", String, "List tables for given identifier and database.", "If used with --list-databases the DATABASE parameter is optional.") {|s| @opts[:list_tables] = s || :all }
        opts.on(      "--stat-tmp", "Show information about the remote temporary directory.", "If no identifier is given check local temp directory instead.") { @opts[:dispatch] = :stat_tmp }
        opts.on(      "--cleanup-tmp", "Remove all temporary files from db_sucker in target directory.") { @opts[:dispatch] = :cleanup_tmp }
        opts.on(      "--simulate", "To use with --cleanup-tmp to not actually remove anything.") { @opts[:simulate] = true }
        opts.separator("\n" << c("# General options", :blue))
        opts.on("-d", "--debug", "Debug output") { @opts[:debug] = true ; logger.enable(:debug) }
        opts.on("-m", "--monochrome", "Don't colorize output") { logger.colorize = false }
        opts.on("-h", "--help", "Shows this help") { @opts[:dispatch] = :help }
        opts.on("-v", "--version", "Shows version and other info") { @opts[:dispatch] = :info }
        opts.on("-z", "Do not check for updates on GitHub (with -v/--version)") { @opts[:check_for_updates] = false }
      end

      begin
        @optparse.parse!(@argv)
      rescue OptionParser::ParseError => e
        abort(e.message)
        dispatch(:help)
        exit 1
      end
    end

    def config_dir
      File.expand_path("~/.db_sucker")
    end

    def config_files
      Dir["#{config_dir}/**/*.yml"].select{|f| File.file?(f) }.reject{|f| File.basename(f).start_with?("_") }
    end

    def load_all_configs
      config_files.each{|f| load_config(f) }
    end

    def load_config file
      cfg.load_cfg(file)
    end
  end
end
