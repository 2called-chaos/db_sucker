module DbSucker
  class Configuration
    attr_reader :app, :data

    def initialize app, file = nil
      @app = app
      @data = {}
      load_cfg(file) if file
    end

    def load_cfg file
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
