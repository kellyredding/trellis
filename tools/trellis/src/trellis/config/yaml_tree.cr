module Trellis
  module Config
    # Reads YAML into a mutable, ordered JSON::Any tree with YAML 1.2 core
    # scalars: plain `off`, `on`, `yes` and `no` stay strings (the schema
    # uses `off` as a value), where Crystal's YAML.parse would read booleans.
    module YamlTree
      extend self

      INT   = /\A[-+]?[0-9]+\z/
      FLOAT = /\A[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?\z/
      NULLS = ["", "~", "null", "Null", "NULL"]
      TRUES = ["true", "True", "TRUE"]
      FALSE = ["false", "False", "FALSE"]

      def parse(text : String) : JSON::Any
        document = YAML::Nodes.parse(text)
        root = document.nodes.first?
        root ? convert(root) : JSON::Any.new(nil)
      rescue error : YAML::ParseException
        raise InvalidConfig.new("the config is not valid YAML", [error.message || "parse error"])
      end

      # What a plain (unquoted) scalar reads as.
      def plain(value : String) : JSON::Any
        return JSON::Any.new(nil) if NULLS.includes?(value)
        return JSON::Any.new(true) if TRUES.includes?(value)
        return JSON::Any.new(false) if FALSE.includes?(value)
        if value.matches?(INT)
          if int = value.to_i64?
            return JSON::Any.new(int)
          end
        end
        return JSON::Any.new(value.to_f) if value.matches?(FLOAT)
        JSON::Any.new(value)
      end

      private def convert(node : YAML::Nodes::Node) : JSON::Any
        case node
        when YAML::Nodes::Scalar
          node.style.plain? ? plain(node.value) : JSON::Any.new(node.value)
        when YAML::Nodes::Sequence
          JSON::Any.new(node.nodes.map { |child| convert(child) })
        when YAML::Nodes::Mapping
          hash = {} of String => JSON::Any
          node.each do |key, value|
            unless key.is_a?(YAML::Nodes::Scalar)
              node.raise("mapping keys must be plain text")
            end
            if hash.has_key?(key.value)
              key.raise("duplicate key #{key.value.inspect}")
            end
            hash[key.value] = convert(value)
          end
          JSON::Any.new(hash)
        when YAML::Nodes::Alias
          target = node.value || node.raise("unknown anchor")
          convert(target)
        else
          node.raise("unsupported YAML node")
        end
      end
    end
  end
end
