module DbSucker
  class Application
    class Container
      module Accessors
        def ctn
          self
        end

        def source
          ctn.data["source"]
        end

        def tmp_path
          source["ssh"]["tmp_location"].presence || "/tmp/db_sucker_tmp"
        end

        def variations
          Hash[data["variations"].keys.map{|id| [id, variation(id)] }]
        end

        def variation v
          return unless vd = data["variations"][v]
          Variation.new(self, v, vd)
        end

        def integrity_binary
          (source["integrity_binary"].nil? ? "shasum -ba" : source["integrity_binary"]).presence
        end

        def integrity_sha
          source["integrity_sha"].nil? ? 512 : source["integrity_sha"]
        end

        def integrity?
          !!integrity_sha
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
      end
    end
  end
end
