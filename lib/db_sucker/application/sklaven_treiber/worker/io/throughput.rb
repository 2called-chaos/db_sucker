module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class Throughput
            InstanceAlreadyRegisteredError = Class.new(::ArgumentError)

            attr_reader :sklaventreiber, :stats

            def initialize sklaventreiber
              @sklaventreiber = sklaventreiber
              @instances = {}
              @stats = {}
              @monitor = Monitor.new
              @polling = []
            end

            def app
              sklaventreiber.app
            end

            def sync &block
              @monitor.synchronize(&block)
            end

            def poll! instance
              sync { @polling.push(instance) }
            end

            def nopoll! instance
              sync { @polling.delete(instance) }
            end

            def start_loop
              @poll = app.spawn_thread(:sklaventreiber_throughput) do |thr|
                thr[:polling] = 0
                loop do
                  sync {
                    thr[:polling] = @polling.length
                    @polling.each(&:ping)
                  }
                  break if thr[:stop]
                  thr.wait(0.1)
                end
              end
            end

            def stop_loop
              sync do
                return unless @poll
                @poll[:stop] = true
              end
              @poll.signal.join
            end

            def commit! bytes, *categories
              sync do
                return unless bytes
                categories.flatten.each do |cat|
                  @stats[cat] ||= 0
                  @stats[cat] += bytes
                end
              end
            end

            def register target
              sync do
                if @instances[target]
                  raise InstanceAlreadyRegisteredError, "throughput manager cannot register more than once on the same target: `#{target}'"
                else
                  raise NotImplementedError, "throughput manager requires the target to respond_to?(:filesize)" unless target.respond_to?(:filesize)
                  raise NotImplementedError, "throughput manager requires the target to respond_to?(:offset)" unless target.respond_to?(:offset)
                  @instances[target] = Instance.new(self, target)
                end
              end
            end

            def unregister instance
              sync do
                @instances.clone.each do |k, v|
                  if v == instance
                    @instances.delete(k)
                    break
                  end
                end
              end
            end

            class Instance
              attr_reader :ioop, :categories, :sopts

              def initialize manager, ioop
                @manager = manager
                @ioop = ioop
                @monitor = Monitor.new
                @pauses = 0
                @categories = [:total]
                @tracking = []
                @tracking_offset = 0
                @sopts = { perc_modifier: 1, perc_base: 0, tracking: 5.seconds }
                reset_stats
              end

              def self.expose what, &how
                define_method(what) do |*args, &block|
                  sync { instance_exec(*args, &how) }
                end
              end

              [:filesize, :offset].each do |m|
                define_method(m) {|*a| @ioop.send(m, *a) }
              end

              [:human_bytes, :human_percentage, :human_seconds, :human_seconds2].each do |m|
                define_method(m) {|*a| @manager.app.send(m, *a) }
              end

              def sync &block
                @monitor.synchronize(&block)
              end

              def commit!
                sync do
                  ping
                  return unless offset
                  @manager.commit!(offset, @categories)
                end
              end

              def pause!
                sync do
                  return if @pause_started
                  @pause_started = Time.current
                end
              end

              def unpause!
                sync do
                  return unless @pause_started
                  @pauses += Time.current - @pause_started
                  @pause_started = false
                end
              end

              def ping
                sync do
                  return unless @started_at
                  @stats[:bps_avg] = runtime.zero? ? 0 : (offset.to_d / runtime.to_d).to_i
                  @stats[:eta2] = @stats[:bps_avg].zero? ? -1 : (bytes_remain.to_d / @stats[:bps_avg].to_d).to_i

                  # eta tracking
                  od = @tracking.last ? offset - @tracking_offset - @tracking.sum{|t,o| o }.to_d : 0
                  @tracking << [Time.current, od] if !od.zero? || @tracking.empty?
                  while @tracking.any? && @tracking.first[0] < @sopts[:tracking].ago
                    @tracking_offset += @tracking.shift[1]
                  end

                  range = @tracking.any? ? @tracking.last[0] - @tracking.first[0] : 0
                  @stats[:bps] = range.zero? ? 0 : @tracking.sum{|t,o| o }.to_d / range.to_d
                  @stats[:eta] = @stats[:bps].zero? ? -1 : (bytes_remain.to_d / @stats[:bps].to_d).to_i
                end
              end

              def unregister
                @manager.unregister(self)
              end

              def reset_stats
                sync do
                  @tracking_offset = 0
                  @tracking.clear
                  @stats = { eta: -1, eta2: -1, bps: 0, bps_avg: 0 }
                end
              end

              # =======
              # = API =
              # =======
              expose(:eta) { ping; @stats[:eta] }
              expose(:eta2) { ping; @stats[:eta2] }
              expose(:bps) { ping; @stats[:bps] }
              expose(:bps_avg) { ping; @stats[:bps_avg] }
              expose(:done_percentage) { @sopts[:perc_base].to_d + @sopts[:perc_modifier].to_d * (filesize == 0 ? 100 : offset == 0 ? 0 : (offset.to_d / filesize.to_d * 100.to_d)) }
              expose(:remain_percentage) { 100.to_d - done_percentage }
              expose(:bytes_remain) { filesize - offset }
              expose(:pauses) { @pauses + (@pause_started ? Time.current - @pause_started : 0) }
              expose(:runtime) { @started_at ? (@ended_at || Time.current) - @started_at - pauses : 0 }
              expose(:f_byte_progress) { "#{f_offset}/#{f_filesize}" }

              [:bps, :bps_avg, :done_percentage, :remain_percentage, :bytes_remain, :offset, :filesize].each do |m|
                expose(:"f_#{m}") { human_bytes(send(m)) }
              end
              [:done_percentage, :remain_percentage].each do |m|
                expose(:"f_#{m}") { human_percentage(send(m)) }
              end
              [:runtime].each do |m|
                expose(:"f_#{m}") { human_seconds(send(m)) }
              end
              [:eta, :eta2].each do |m|
                expose(:"f_#{m}") { r = send(m); r == -1 ? "?:¿?:¿?" : human_seconds2(send(m)) }
              end

              def measure &block
                @manager.poll!(self)
                @started_at = Time.current
                block.call(self)
              ensure
                @ended_at = Time.current
                @manager.nopoll!(self)
                commit!
              end
            end
          end
        end
      end
    end
  end
end
