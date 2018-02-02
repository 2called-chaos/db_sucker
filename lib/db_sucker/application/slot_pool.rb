module DbSucker
  class Application
    class SlotPool
      SlotAllocationError = Class.new(::RuntimeError)
      PoolAlreadyClosedError = Class.new(SlotAllocationError)

      def initialize slots = 1, name = nil
        @name = name
        @slots = slots
        @monitor = Monitor.new
        @closed = false
        @softclosed = false
        @waiting = []
        @active = []
        @signal = @monitor.new_cond
        @closed_signal = @monitor.new_cond
      end

      def self.expose what, &how
        define_method(what) do |*args, &block|
          sync { instance_exec(*args, &how) }
        end
      end

      def sync &block
        @monitor.synchronize(&block)
      end

      expose(:name) { @name }
      expose(:active) { @active }
      expose(:active?) { @active.any? }
      expose(:waiting) { @waiting }
      expose(:waiting?) { @waiting.any? }
      expose(:closed?) { @closed }
      expose(:softclosed?) { @softclosed }
      expose(:slots) { @slots }
      expose(:available_slots) { @slots ? @slots - @active.length : 1.0/0 }
      expose(:slots?) { @slots ? available_slots > 0 : true }

      def close
        sync do
          @closed = true
          @signal.broadcast
        end
        true
      end

      def close!
        sync do
          close
          @closed_signal.wait if active?
        end
      end

      def softclose!
        @softclosed = true
        dequeue_waiting!
      end

      def dequeue_waiting!
        sync do
          while @waiting.any?
            _wthr, _tthr = @waiting.shift
            _wthr.signal
          end
          @signal.broadcast
        end
      end

      def qindex thr = nil
        thr ||= Thread.current
        sync do
          index = @waiting.find_index {|wthr, tthr| tthr == thr }
          index ? index + 1 : false
        end
      end

      def puts *a
        Thread.main[:app].puts(*a)
      end

      def aquired? tthr = nil
        @active.include?(tthr || Thread.current)
      end

      def wait_aquired tthr = nil
        tthr ||= Thread.current
        #tthr.wait(0.1) until qindex(tthr)
        loop do
          sync do
            #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> wait for index"
            #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> has #{available_slots} slots"
            while slots? && @waiting.any?
              _wthr, _tthr = @waiting.shift
              #puts "<#{Time.current.to_f}-#{_tthr[:current_task]}> running now"
              @active.push(_tthr) unless @softclosed
              _tthr.signal
              _wthr.signal
            end
            unless qindex(tthr)
              #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> return"
              return
            end
            #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> wait"
            @signal.wait #(1)
            #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> wait DONE"
          end
        end
      end

      def aquire tthr = nil
        wthr = Thread.current
        tthr ||= Thread.current
        sync do
          raise PoolAlreadyClosedError, "slot pool has already been closed, cannot aquire slot" if closed?
          @waiting << [wthr, tthr]
          #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> broadcasting signal after adding new waiter"
          @signal.broadcast # signal polling threads
        end
        tthr.signal # signal target thread to continue and poll
        wthr.wait # suspend thread until we aquired it
        true
      end

      def release tthr = nil
        sync do
          tthr ||= Thread.current
          ai = @active.delete(tthr)
          return unless ai
          #puts "<#{Time.current.to_f}-#{tthr[:current_task]}> broadcasting signal"
          @signal.broadcast
          @closed_signal.broadcast if @active.empty? && closed?
        end
      end
    end
  end
end
