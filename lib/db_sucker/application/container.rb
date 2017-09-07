module DbSucker
  class Application
    class Container
      include SSH
      attr_reader :name, :src, :data
      OutputHelper.hook(self)

      def initialize name, src, data
        @name = name
        @src = src
        @data = data
        @ssh_mutex = Monitor.new
        @sftp_mutex = Monitor.new

        verify!

        begin
          extend "DbSucker::Adapters::#{@data["source"]["adapter"].camelize}::RPC".constantize
        rescue NameError => ex
          raise(ex, "identifier `#{name}' defines invalid source adapter `#{@data["source"]["adapter"]}' (in `#{@src}'): #{ex.message}", ex.backtrace)
        end
      end

      def _verify token, hash, keys
        begin
          hash.assert_valid_keys(keys)
          raise ArgumentError, "A source must define an adapter (mysql2, postgres, ...)" if token == "/source" && hash["adapter"].blank?
          raise ArgumentError, "A variation `#{name}' can only define either a `only' or `except' option" if hash["only"] && hash["except"]
        rescue ArgumentError => ex
          abort "#{ex.message} (in `#{src}' [#{token}])"
        end
      end

      def __keys_for which
        {
          root: %w[source variations],
          source: %w[adapter ssh database hostname username password args binary],
          source_ssh: %w[hostname username keyfile password port tmp_location],
          variation: %w[adapter label base database hostname username password args incremental file gzip only except importer ignore_always constraints],
        }[which] || []
      end

      def verify!
        _verify("/", data, __keys_for(:root))

        # validate source
        if sd = data["source"]
          _verify("/source", sd, __keys_for(:source))
          if sd["ssh"]
            _verify("/source/ssh", sd["ssh"], __keys_for(:source_ssh))
            ssh_key_files
          end
        end

        # validate variations
        if sd = data["variations"]
          sd.each do |name, vd|
            _verify("/variations/#{name}", vd, __keys_for(:variation))
            base = sd[vd["base"]] if vd["base"]
            raise(ArgumentError, "variation `#{name}' cannot base from `#{vd["base"]}' since it doesn't exist (in `#{src}')") if vd["base"] && !base
            raise ArgumentError, "variation `#{name}' must define an adapter (mysql2, postgres, ...)" if vd["adapter"].blank? && (!base || base["adapter"].blank?)
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
              warning("SSH identity file `#{f}' for identifier `#{name}' does not exist! (in `#{src}')")
            end
          end
          files
        end
      end

      def source_database
        data["source"]["database"]
      end

      def tmp_path
        data["source"]["ssh"]["tmp_location"].presence || "/tmp/db_sucker_tmp"
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