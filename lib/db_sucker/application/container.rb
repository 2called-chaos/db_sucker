module DbSucker
  class Application
    class Container
      AdapterNotFoundError = Class.new(::ArgumentError)
      TableNotFoundError = Class.new(::RuntimeError)
      ConfigurationError = Class.new(::ArgumentError)

      include Accessors
      include Validations
      include SSH
      OutputHelper.hook(self)

      attr_reader :app, :name, :src, :data

      def initialize app, name, src, data
        @app = app
        @name = name
        @src = src
        @data = data
        @ssh_mutex = Monitor.new
        @sftp_mutex = Monitor.new

        verify!

        begin
          adapter = "DbSucker::Adapters::#{source["adapter"].camelize}::Api".constantize
          adapter.require_dependencies
          extend adapter
        rescue NameError => ex
          raise(AdapterNotFoundError, "identifier `#{name}' defines invalid source adapter `#{source["adapter"]}' (in `#{@src}'): #{ex.message}", ex.backtrace)
        end
      end

      def pv_utility
        if @_pv_utility.nil?
          ssh_start(true) do |ssh|
            res = blocking_channel_result("which pv && pv --version", ssh: ssh)
            if m = res[1].to_s.match(/pv\s([0-9\.]+)\s/i)
              if Gem::Version.new(m[1]) >= Gem::Version.new("1.3.8")
                @_pv_utility = res[0].strip.presence
              end
            end
          end if app.opts[:pv_enabled]
          @_pv_utility = false unless @_pv_utility
        end
        @_pv_utility
      end

      def calculate_remote_integrity_hash file, blocking = true
        return unless integrity?
        cmd = %{#{integrity} #{file}}
        [cmd, blocking_channel_result(cmd, channel: true, request_pty: true, blocking: blocking)]
      end
    end
  end
end
