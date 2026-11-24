module Trellis
  module Config
    # Reads the config's JSON into a mutable, ordered tree. Strict JSON, and a
    # repeated key is an error where JSON.parse would keep the last silently.
    module Reader
      extend self

      def parse(text : String) : JSON::Any
        tree = JSON.parse(text)
        reject_duplicates(JSON::PullParser.new(text))
        tree
      rescue error : JSON::ParseException
        raise InvalidConfig.new("the config is invalid", ["not valid JSON: #{error.message}"])
      end

      private def reject_duplicates(pull : JSON::PullParser) : Nil
        case pull.kind
        when .begin_object?
          seen = Set(String).new
          pull.read_object do |key, location|
            unless seen.add?(key)
              raise JSON::ParseException.new("duplicate key #{key.inspect}", *location)
            end
            reject_duplicates(pull)
          end
        when .begin_array?
          pull.read_array { reject_duplicates(pull) }
        else
          pull.skip
        end
      end
    end
  end
end
