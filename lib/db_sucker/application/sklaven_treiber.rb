module DbSucker
  class Application
    class SklavenTreiber
      attr_reader :app, :trxid, :window, :data, :status, :monitor, :workers, :poll, :throughput

      def initialize app, trxid
        @app = app
        @trxid = trxid
        @status = ["initializing", "gray"]
        @monitor = Monitor.new
        @workers = []
        @threads = []
        @sleep_before_exit = 0
        @throughput = Worker::IO::Throughput.new(self)

        @data = {
          database: nil,
          tables_transfer: nil,
          tables_transfer_list: [],
          tables_total: nil,
          tables_done: 0,
        }
      end

      def sync
        @monitor.synchronize { yield }
      end

      def whip_it! ctn, var
        @ctn, @var = ctn, var

        _init_window
        _check_remote_tmp_directory
        _select_tables
        _initialize_workers
        _start_ssh_poll
        @throughput.start_loop

        @sleep_before_exit = 3
        _run_consumers
      ensure
        app.sandboxed do
          @status = ["terminating (canceling workers)", "red"]
          @workers.each(&:cancel!)
        end
        app.sandboxed do
          @status = ["terminating (SSH poll)", "red"]
          @poll.try(:join)
        end
        @status = ["terminated", "red"]
        sleep @sleep_before_exit
        app.sandboxed { @window.try(:stop) }
        app.sandboxed { @ctn.try(:sftp_end) }
        app.sandboxed { @throughput.try(:stop_loop) }
        app.sandboxed do
          app.puts @window.try(:_render_final_results)
        end
        @ctn, @var = nil, nil
      end

      def _init_window
        return unless app.opts[:window_enabled]
        @window = Window.new(app, self)
        @window.init!
        @window.start
      end

      def _check_remote_tmp_directory
        @status = ["checking remote temp directory", "blue"]
        @ctn.sftp_begin
        @ctn.sftp_start do |sftp|
          # check tmp directory
          app.debug "Checking remote temp directory #{app.c @ctn.tmp_path, :magenta}"
          begin
            sftp.dir.glob("#{@ctn.tmp_path}", "**/*")
          rescue Net::SFTP::StatusException => ex
            if ex.message["no such file"]
              app.abort "Temp directory `#{@ctn.tmp_path}' does not exist on the remote side!", 2
            else
              raise
            end
          end
        end
      end

      def _select_tables
        @status = ["selecting tables for transfer", "blue"]
        ttt, at = @var.tables_to_transfer

        # apply only/except filters provided via command line
        if @app.opts[:suck_only].any? && @app.opts[:suck_except].any?
          raise OptionParser::InvalidArgument, "only one of `--only' or `--except' option can be provided at the same time"
        elsif @app.opts[:suck_only].any?
          unless (r = @app.opts[:suck_only] - at).empty?
            raise Container::TableNotFoundError, "table(s) `#{r * ", "}' for the database `#{@ctn.source["database"]}' could not be found (provided via --only, variation `#{@ctn.name}/#{@var.name}' in `#{@ctn.src}')"
          end
          ttt = @app.opts[:suck_only]
        elsif @app.opts[:suck_except].any?
          unless (r = @app.opts[:suck_except] - at).empty?
            raise Container::TableNotFoundError, "table(s) `#{r * ", "}' for the database `#{@ctn.source["database"]}' could not be found (provided via --except, variation `#{@ctn.name}/#{@var.name}' in `#{@ctn.src}')"
          end
          ttt = ttt - @app.opts[:suck_except]
        end

        @data[:database] = @ctn.source["database"]
        @data[:tables_transfer] = ttt.length
        @data[:tables_transfer_list] = ttt
        @data[:window_col1] = ttt.map(&:length).max
        @data[:tables_total] = at.length
      end

      def _initialize_workers
        @status = ["initializing workers 0/#{@data[:tables_transfer]}", "blue"]

        @data[:tables_transfer_list].each_with_index do |table, index|
          @status = ["initializing workers #{index+1}/#{@data[:tables_transfer]}", "blue"]
          @workers << Worker.new(self, @ctn, @var, table)
        end
      end

      def _start_ssh_poll
        @poll = Thread.new do
          Thread.current[:itype] = :sklaventreiber_ssh_poll
          Thread.current.priority = @app.opts[:tp_sklaventreiber_ssh_poll]
          Thread.current[:iteration] = 0
          @ctn.loop_ssh(0.1) {
            Thread.current[:iteration] += 1
            Thread.current[:last_iteration] = Time.current
            @workers.select{|w| !w.done? || w.sshing }.any?
          }
        end
      end

      def _run_consumers
        cnum = [app.opts[:consumers], @data[:tables_transfer]].min
        @data[:window_col2] = cnum.to_s.length
        if cnum <= 1
          _run_in_main_thread
        else
          _run_in_threads(cnum)
        end
      end

      def _run_in_main_thread
        @status = ["running in main thread...", "green"]

        # control thread
        ctrlthr = Thread.new do
          Thread.current[:itype] = :sklaventreiber_worker_ctrl
          Thread.current.priority = @app.opts[:tp_sklaventreiber_worker_ctrl]
          loop do
            if $core_runtime_exiting && $core_runtime_exiting < 100
              $core_runtime_exiting += 100
              @workers.each(&:cancel!)
              Thread.current[:stop] = true
            end
            break if Thread.current[:stop]
            sleep 0.1
          end
        end

        begin
          _queueoff
        ensure
          ctrlthr[:stop] = true
          ctrlthr.join
        end
      end

      def _run_in_threads(cnum)
        @status = ["starting consumer 0/#{cnum}", "blue"]

        # initializing consumer threads
        cnum.times do |wi|
          @status = ["starting consumer #{wi+1}/#{cnum}", "blue"]
          @threads << Thread.new {
            Thread.current[:itype] = :sklaventreiber_worker
            Thread.current.priority = @app.opts[:tp_sklaventreiber_worker]
            Thread.current[:managed_worker] = wi
            sleep 0.1 until Thread.current[:start] || $core_runtime_exiting
            _queueoff
          }
        end

        # start consumer threads
        @status = ["running", "green"]
        @threads.each{|t| t[:start] = true }

        # master thread (control)
        while @threads.any?(&:alive?)
          if $core_runtime_exiting && $core_runtime_exiting < 100
            $core_runtime_exiting += 100
            @workers.each(&:cancel!)
          end
          sleep 0.1
        end
        @threads.each(&:join)
      end

      def _queueoff
        loop do
          return if $core_runtime_exiting
          worker = false
          sync do
            pending = @workers.select(&:pending?)
            return unless pending.any?
            worker = pending.first.aquire(Thread.current)
          end
          if worker
            begin
              worker.run
            ensure
              sync { @data[:tables_done] += 1 }
            end
          end
        end
      end
    end
  end
end
