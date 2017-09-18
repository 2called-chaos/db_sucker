module DbSucker
  class Application
    class Container
      class Variation
        module Helpers
          def parse_flags flags
            flags.to_s.split(" ").map(&:strip).reject(&:blank?).each_with_object({}) do |fstr, res|
              if m = fstr.match(/\+(?<key>[^=]+)(?:=(?<value>))?/)
                res[m[:key].strip] = m[:value].nil? ? true : m[:value]
              elsif m = fstr.match(/\-(?<key>[^=]+)/)
                res[m[:key]] = false
              else
                raise InvalidImporterFlagError, "invalid flag `#{fstr}' for variation `#{cfg.name}/#{name}' (in `#{cfg.src}')"
              end
            end
          end
        end
      end
    end
  end
end
