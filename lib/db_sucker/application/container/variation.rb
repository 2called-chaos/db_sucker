module DbSucker
  class Application
    class Container
      class Variation
        ImporterNotFoundError = Class.new(::RuntimeError)
        InvalidImporterFlagError = Class.new(::RuntimeError)

        include Accessors
        include Helpers
        include WorkerApi

        attr_reader :cfg, :name, :data

        def initialize cfg, name, data
          @cfg, @name, @data = cfg, name, data

          if data["base"]
            bdata = cfg.variation(data["base"]) || raise(ConfigurationError, "variation `#{cfg.name}/#{name}' cannot base from `#{data["base"]}' since it doesn't exist (in `#{cfg.src}')")
            @data = data.reverse_merge(bdata.data)
          end

          if @data["adapter"]
            begin
              adapter = "DbSucker::Adapters::#{@data["adapter"].camelize}::Api".constantize
              adapter.require_dependencies
              extend adapter
            rescue NameError => ex
              raise(AdapterNotFoundError, "variation `#{cfg.name}/#{name}' defines invalid adapter `#{@data["adapter"]}' (in `#{cfg.src}'): #{ex.message}", ex.backtrace)
            end
          elsif @data["database"]
            raise(ConfigurationError, "variation `#{cfg.name}/#{name}' must define an adapter (mysql2, postgres, ...) if database is provided (in `#{cfg.src}')")
          end
        end

        # ===============
        # = Adapter API =
        # ===============
        [
          :client_binary,
          :local_client_binary,
          :dump_binary,
          :client_call,
          :local_client_call,
          :dump_call,
          :database_list,
          :table_list,
          :hostname,
        ].each do |meth|
          define_method meth do
            raise NotImplementedError, "your selected adapter `#{@data["adapter"]}' must implement `##{meth}' for variation `#{cfg.name}/#{name}' (in `#{cfg.src}')"
          end
        end

        def dump_command_for table
          raise NotImplementedError, "your selected adapter `#{@data["adapter"]}' must implement `#dump_command_for(table)' for variation `#{cfg.name}/#{name}' (in `#{cfg.src}')"
        end
      end
    end
  end
end
