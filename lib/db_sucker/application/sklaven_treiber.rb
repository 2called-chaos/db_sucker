module DbSucker
  class Application
    class SklavenTreiber
      attr_reader :app, :trxid, :window, :data, :status, :monitor, :workers, :poll, :throughput, :slot_pools

      def initialize app, trxid
        @app = app
        @trxid = trxid
        @status = ["initializing", "gray"]
        @monitor = Monitor.new
        @workers = []
        @threads = []
        @slot_pools = {}
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

      def pause_worker worker
        sync { worker.pause }
      end

      def unpause_worker worker
        sync { worker.unpause }
      end

      def pause_all_workers
        sync { @workers.each {|wrk| pause_worker(wrk) } }
      end

      def unpause_all_workers
        sync { @workers.each {|wrk| unpause_worker(wrk) } }
      end

      def spooled
        stdout_was = app.opts[:stdout]
        app.opts[:stdout] = SklavenTreiber::LogSpool.new(stdout_was) if app.opts[:window_enabled]
        yield if block_given?
      ensure
        app.opts[:stdout].spooldown do |meth, args, time|
          stdout_was.send(meth, *args)
        end if app.opts[:stdout].respond_to?(:spooldown)
        app.opts[:stdout] = stdout_was
      end

      def whip_it! ctn, var
        @ctn, @var = ctn, var

        _start_ssh_poll
        _init_window
        _check_remote_tmp_directory
        _select_tables
        _initialize_slot_pools
        _initialize_workers
        @ctn.pv_utility # lazy load
        @poll[:force] = false
        @throughput.start_loop

        @sleep_before_exit = 3 if @window
        _run_consumers
      ensure
        app.sandboxed do
          @status = ["terminating (canceling workers)", "red"]
          @workers.each {|w| catch(:abort_execution) { w.cancel! } }
        end
        app.sandboxed do
          @status = ["terminating (SSH poll)", "red"]
          if @poll
            @poll[:force] = false
            @poll.join
          end
        end
        @status = ["terminated", "red"]
        sleep @sleep_before_exit
        app.sandboxed { @window.try(:stop) }
        app.sandboxed { @ctn.try(:sftp_end) }
        app.sandboxed { @throughput.try(:stop_loop) }
        app.sandboxed { @slot_pools.each{|n, p| p.close! } }
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

      def _initialize_slot_pools
        app.opts[:slot_pools].each do |name, slots|
          @slot_pools[name] = SlotPool.new(slots, name)
        end
      end

      def _initialize_workers
        @status = ["initializing workers 0/#{@data[:tables_transfer]}", "blue"]

        @data[:tables_transfer_list].each_with_index do |table, index|
          @status = ["initializing workers #{index+1}/#{@data[:tables_transfer]}", "blue"]
          @workers << Worker.new(self, @ctn, @var, table)
        end
      end

      def _start_ssh_poll
        wait_lock = Queue.new
        @poll = app.spawn_thread(:sklaventreiber_ssh_poll) do |thr|
          thr[:force] = true
          thr[:iteration] = 0
          thr[:errors] = 0
          wait_lock << true
          begin
            @ctn.loop_ssh(0.1) {
              thr[:iteration] += 1
              thr[:last_iteration] = Time.current
              thr[:force] || @workers.select{|w| !w.done? || w.sshing }.any?
            }
          rescue Container::SSH::ChannelOpenFailedError
            thr[:errors] += 1
            sleep 0.5
            retry
          end

          if thr[:errors].zero?
            app.debug "SSH error count (#{thr[:errors]})"
          elsif thr[:errors] > 25
            app.warning "SSH error count (#{thr[:errors]}) is high! Verify remote MaxSessions setting or lower concurrent worker count."
          else
            app.warning "SSH errors occured (#{thr[:errors]})! Verify remote MaxSessions setting or lower concurrent worker count."
          end
        end
        wait_lock.pop
        sleep 0.01 until @poll[:iteration] && @poll[:iteration] > 0
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
        ctrlthr = app.spawn_thread(:sklaventreiber_worker_ctrl) do |thr|
          loop do
            _control_thread
            break if thr[:stop]
            thr.wait(0.1)
          end
        end

        begin
          Thread.current[:managed_worker] = :main
          _queueoff
        ensure
          ctrlthr[:stop] = true
          ctrlthr.signal.join
        end
      end

      def _run_in_threads(cnum)
        @status = ["starting consumer 0/#{cnum}", "blue"]

        # initializing consumer threads
        cnum.times do |wi|
          @status = ["starting consumer #{wi+1}/#{cnum}", "blue"]
          @threads << app.spawn_thread(:sklaventreiber_worker) {|thr|
            begin
              thr[:managed_worker] = wi
              thr.wait(0.1) until thr[:start] || $core_runtime_exiting
              _queueoff
            rescue Interrupt
            end
          }
        end

        # start consumer threads
        @status = ["running", "green"]
        @threads.each{|t| t[:start] = true; t.signal }

        # master thread (control)
        additionals = 0
        Thread.current[:summon_workers] = 0
        while @threads.any?(&:alive?)
          _control_thread
          Thread.current.sync do
            Thread.current[:summon_workers].times do
              app.debug "Spawned additional worker due to deferred import to prevent softlocks"
              @threads << app.spawn_thread(:sklaventreiber_worker) {|thr|
                begin
                  additionals += 1
                  thr[:managed_worker] = cnum + additionals
                  _queueoff
                rescue Interrupt
                end
              }
            end
            Thread.current[:summon_workers] = 0
          end
          Thread.current.wait(0.1)
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

      def _control_thread
        if $core_runtime_exiting && $core_runtime_exiting < 100
          $core_runtime_exiting += 100
          app.sandboxed { @workers.each {|w| catch(:abort_execution) { w.cancel! } } }
          app.sandboxed { @slot_pools.each{|n, p| p.softclose! } }
          app.wakeup_handlers
        end
      end
    end
  end
end
