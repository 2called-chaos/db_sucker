module DbSucker
  class Application
    class Container
      module Validations
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
              begin
                _verify("/variations/#{name}", vd, __keys_for(:variation))
                base = sd[vd["base"]] if vd["base"]
                raise(ConfigurationError, "variation `#{name}' cannot base from `#{vd["base"]}' since it doesn't exist (in `#{src}')") if vd["base"] && !base
                raise ConfigurationError, "variation `#{name}' must define an adapter (mysql2, postgres, ...)" if vd["adapter"].blank? && vd["database"] != false && (!base || base["adapter"].blank?)
              rescue ConfigurationError => ex
                abort "#{ex.message} (in `#{src}' [/variations/#{name}])"
              end
            end
          end
        end

        def _verify token, hash, keys
          begin
            hash.assert_valid_keys(keys)
            raise ConfigurationError, "A source must define an adapter (mysql2, postgres, ...)" if token == "/source" && hash["adapter"].blank?
            raise ConfigurationError, "A variation `#{name}' can only define either a `only' or `except' option" if hash["only"] && hash["except"]
          rescue ConfigurationError, ArgumentError => ex
            abort "#{ex.message} (in `#{src}' [#{token}])"
          end
        end

        def __keys_for which
          {
            root: %w[source variations],
            source: %w[adapter ssh database hostname username password args client_binary dump_binary gzip_binary integrity_sha integrity_binary],
            source_ssh: %w[hostname username keyfile password port tmp_location],
            variation: %w[adapter label base database hostname username password args client_binary incremental file only except importer importer_flags ignore_always constraints],
          }[which] || []
        end
      end
    end
  end
end
