module DbSucker
  class Application
    class Container
      class Variation
        module Accessors
          def ctn
            cfg
          end

          def source
            ctn.source
          end

          def label
            data["label"]
          end

          def incrementals
            data["incremental"] || {}
          end

          def gzip_binary
            source["gzip_binary"] || "gzip"
          end

          def integrity
            (data["integrity"].nil? ? "shasum -ba512" : data["integrity"]).presence
          end

          def integrity?
            ctn.integrity? && integrity
          end

          def copies_file?
            data["file"]
          end

          def copies_file_compressed?
            copies_file? && data["file"].end_with?(".gz")
          end

          def requires_uncompression?
            !copies_file_compressed? || data["database"]
          end

          def constraint table
            data["constraints"] && (data["constraints"][table] || data["constraints"]["__default"])
          end
        end
      end
    end
  end
end
