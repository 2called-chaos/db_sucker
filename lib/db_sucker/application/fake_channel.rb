module DbSucker
  class Application
    class FakeChannel
      def initialize &block
        @storage = {}
        @termination = block
      end

      def [] k
        @storage[k]
      end

      def []= k, v
        @storage[k] = v
      end

      def alive?
        !@termination.try(:call, self)
      end
    end
  end
end
