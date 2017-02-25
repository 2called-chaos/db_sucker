module DbSucker
  class Application
    class ContainerCollection
      attr_reader :app, :data

      def initialize app
        @app = app
        @data = {}
      end

      def yml_configs disabled = false
        files = Dir["#{app.core_cfg_path}/**/*.yml"].select{|f| File.file?(f) }
        return files if disabled
        files.reject do |f|
          f.gsub("#{app.core_cfg_path}/", "").split("/").any?{|fp| fp.start_with?("__") }
        end
      end

      def load_all_configs
        yml_configs.each{|f| load_yml_config(f) }
      end

      def load_yml_config file
        YAML.load_file(file).each do |id, cfg|
          if @data.key?(id)
            raise "double use of identifier `#{id}' in `#{file}'"
          else
            @data[id] = Container.new(id, file, cfg)
          end
        end
      end

      def get id
        @data[id]
      end

      def each &block
        @data.each(&block)
      end
    end
  end
end
