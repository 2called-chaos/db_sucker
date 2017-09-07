module DbSucker
  class Application
    class SklavenTreiber
      attr_reader :app, :trxid, :window, :data, :status, :monitor, :workers

      def initialize app, trxid
        @app = app
        @trxid = trxid
        @status = ["initializing", "gray"]
        @monitor = Monitor.new
        @workers = []
        @threads = []
        @sleep_before_exit = 0

        @data = {
          database: nil,
          tables_transfer: nil,
          tables_total: nil,
          tables_done: 0,
        }
      end

      def sync
        @monitor.synchronize { yield }
      end

      def whip_it! ctn, var
        @ctn, @var = ctn, var
        @window = Window.new(app, self)
        @window.init!
        @window.start_loop(app.opts[:window_refresh_delay])

        # selecting tables
        @status = ["selecting tables for transfer", "blue"]
        ttt, at = var.tables_to_transfer
        @data[:database] = ctn.source_database
        @data[:tables_transfer] = ttt.length
        @data[:window_col1] = ttt.map(&:length).max
        @data[:tables_total] = at.length

        # check tmp directory
        @status = ["checking remote temp directory", "blue"]
        ctn.sftp_begin
        ctn.sftp_start do |sftp|
          # check tmp directory
          app.debug "Checking remote temp directory #{app.c ctn.tmp_path, :magenta}"
          begin
            sftp.dir.glob("#{ctn.tmp_path}", "**/*")
          rescue Net::SFTP::StatusException => ex
            if ex.message["no such file"]
              app.abort "Temp directory `#{ctn.tmp_path}' does not exist on the remote side!", 2
            else
              raise
            end
          end
        end

        # initializing workers
        @status = ["initializing workers 0/#{@data[:tables_transfer]}", "blue"]

        ttt.each_with_index do |table, index|
          @status = ["initializing workers #{index+1}/#{@data[:tables_transfer]}", "blue"]
          @workers << Worker.new(self, ctn, var, table)
        end

        # # poll ssh
        # @poll = Thread.new do
        #   ctn.loop_ssh(0.1) { workers.any? || active_workers.any?(&:active?) }
        # end

        # starting consumers
        @sleep_before_exit = 5
        cnum = [app.opts[:consumers], @data[:tables_transfer]].min
        @data[:window_col2] = cnum.to_s.length
        if cnum <= 1
          @status = ["running in main thread...", "green"]
          _queueoff
        else
          @status = ["starting consumer 0/#{cnum}", "blue"]

          cnum.times do |wi|
            @status = ["starting consumer #{wi+1}/#{cnum}", "blue"]
            @threads << Thread.new {
              Thread.current.abort_on_exception = true
              Thread.current[:managed_worker] = wi
              sleep 0.1 until Thread.current[:start] || $core_runtime_exiting
              _queueoff
            }
          end
          @status = ["running", "green"]
          @threads.each{|t| t[:start] = true }

          # master thread
          while @threads.any?(&:alive?)
            if $core_runtime_exiting && $core_runtime_exiting < 100
              $core_runtime_exiting += 100
              @workers.each(&:cancel!)
            end
            sleep 0.1
          end
          @threads.each(&:join)
        end
      ensure
        # app.sandboxed do
        #   @status = ["terminating (SSH poll)", "red"]
        #   @poll.join
        # end
        @status = ["terminated", "red"]
        sleep @sleep_before_exit
        app.sandboxed { @window.close }
        app.sandboxed { @ctn.sftp_end }
        @ctn, @var = nil, nil
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
