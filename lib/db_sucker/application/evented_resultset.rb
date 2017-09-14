module DbSucker
  class Application
    class EventedResultset
      SetAlreadyClosed = Class.new(::RuntimeError)
      include Enumerable

      def initialize
        @store = []
        @monitor = Monitor.new
        @closed = false
        @close_signal = @monitor.new_cond
        @value_signal = @monitor.new_cond
      end

      def sync &block
        @monitor.synchronize(&block)
      end

      def enq data, group = nil
        sync do
          raise SetAlreadyClosed, "failed to enqueue data: resultset is already closed" if closed?
          @store << [group.try(:to_sym), data]
          @value_signal.broadcast
        end
      end

      def push *args
        sync do
          args.each {|a| enq(a) }
          @store
        end
      end
      alias_method :<<, :push

      def close!
        sync do
          @closed = true
          @value_signal.broadcast
          @close_signal.broadcast
        end
        true
      end

      def closed?
        sync { @closed }
      end

      def empty?
        sync { @store.empty? }
      end

      def wait
        sync do
          return if closed?
          @close_signal.wait
        end
        true
      end

      def for_group group
        @store.map{|grp, data| grp == group.try(:to_sym) ? data : nil }.compact
      end

      def each &block
        wait
        if block
          @store.each do |group, data|
            block.call(data)
          end
        else
          @store.map(&:second)
        end
      end

      def join *a
        wait
        each.join(*a)
      end

      def [] which
        wait
        @store[which].try(:last)
      end

      def eachx &block
        wait
        @store.each(&block)
      end

      def each_line &block
        Thread.current[self.object_id.to_s] = nil
        loop do
          data = gets
          if !data
            break if closed?
            next
          end
          block.call(data)
        end
      ensure
        Thread.current[self.object_id.to_s] = nil
      end

      def each_linex &block
        Thread.current[self.object_id.to_s] = nil
        loop do
          group, entry = getx
          unless entry
            break if closed?
            next
          end
          block.call(group, entry)
        end
      ensure
        Thread.current[self.object_id.to_s] = nil
      end

      def gets
        sync do
          Thread.current[self.object_id.to_s] ||= -1
          if !closed? && !@store[Thread.current[self.object_id.to_s]+1]
            @value_signal.wait
          end
          Thread.current[self.object_id.to_s] += 1
          @store[Thread.current[self.object_id.to_s]].try(:last)
        end
      end

      def getx
        sync do
          Thread.current[self.object_id.to_s] ||= -1
          if !closed? && !@store[Thread.current[self.object_id.to_s]+1]
            @value_signal.wait
          end
          Thread.current[self.object_id.to_s] += 1
          @store[Thread.current[self.object_id.to_s]]
        end
      end
    end
  end
end
