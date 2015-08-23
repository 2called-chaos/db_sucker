module DbSucker
  class Configuration
    class Container
      include RPC
      include Application::LoggerClient
      attr_reader :name, :src, :data

      def initialize name, src, data
        @name = name
        @src = src
        @data = data
        @ssh_mutex = Monitor.new
        @sftp_mutex = Monitor.new

        verify!
      end

      def fail msg
        raise "#{msg} for `#{name}'"
      end

      def verify!
        data.assert_valid_keys %w[source variations]
        if data["source"]
          data["source"].assert_valid_keys %w[ssh database hostname username password args]
          data["source"]["ssh"].assert_valid_keys %w[hostname username keyfile password port tmp_location] if data["source"]["ssh"]
          ssh_key_files
        end

        if data["variations"]
          data["variations"].each do |name, vd|
            vd.assert_valid_keys %w[label base database hostname username password args incremental file gzip only except]
            raise "A variation `#{name}' can only define either a `only' or `except' option in #{src}" if vd["only"] && vd["except"]
          end
        end
      end

      def ssh_key_files
        @ssh_key_files ||= begin
          files = [*data["source"]["ssh"]["keyfile"]].reject(&:blank?).map do |f|
            if f.start_with?("~")
              Pathname.new(File.expand_path(f))
            else
              Pathname.new(File.dirname(src)).join(f)
            end
          end
          files.each do |f|
            begin
              File.open(f)
            rescue Errno::ENOENT
              logger.warn("SSH identity file `#{f}' for identifier `#{name}' does not exist! (in #{src})")
            end
          end
          files
        end
      end

      def tmp_path
        data["source"]["ssh"]["tmp_location"].presence
      end

      def variations
        Hash[data["variations"].map{|id, vd| [id, Variation.new(self, id, vd)] }]
      end

      def variation v
        return unless vd = data["variations"][v]
        Variation.new(self, v, vd)
      end
    end
  end
end
