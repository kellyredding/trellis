module Trellis
  module Config
    # Writes a config tree back out as YAML in the starter's style: sections in
    # block form, placements and region details in flow form. Key order is
    # kept; comments are not, since the tree holds none.
    module Emitter
      extend self

      PLAIN = /\A[A-Za-z0-9_][A-Za-z0-9_+.\-\/]*\z/

      def emit(root : Hash(String, JSON::Any)) : String
        String.build do |io|
          root.each_with_index do |(key, value), index|
            io << '\n' if index > 0
            case key
            when "placements" then section(io, key, value, flow_from: 1, align: true)
            when "regions"    then section(io, key, value, flow_from: 2)
            else                   section(io, key, value, flow_from: Int32::MAX)
            end
          end
        end
      end

      private def section(io : IO, key : String, value : JSON::Any, flow_from : Int32, align : Bool = false) : Nil
        if (hash = value.as_h?) && !hash.empty?
          io << scalar_key(key) << ":\n"
          block(io, hash, 1, flow_from, align)
        else
          io << scalar_key(key) << ':'
          rendered = flow(value)
          io << ' ' << rendered unless rendered.empty?
          io << '\n'
        end
      end

      private def block(io : IO, hash : Hash(String, JSON::Any), depth : Int32, flow_from : Int32, align : Bool = false) : Nil
        width = align ? hash.keys.max_of { |key| scalar_key(key).size + 1 } : 0
        hash.each do |key, value|
          if depth >= flow_from || !value.as_h? || value.as_h.empty?
            io << "  " * depth << (scalar_key(key) + ":").ljust(width)
            rendered = flow(value)
            io << ' ' << rendered unless rendered.empty?
            io << '\n'
          else
            io << "  " * depth << scalar_key(key) << ":\n"
            block(io, value.as_h, depth + 1, flow_from)
          end
        end
      end

      # A value on one line. A bare null renders as nothing (`key:`), which
      # reads back as null.
      private def flow(value : JSON::Any, nested : Bool = false) : String
        case raw = value.raw
        when Hash
          return "{}" if raw.empty?
          "{ " + raw.map { |key, item| "#{scalar_key(key)}: #{flow(item, true)}" }.join(", ") + " }"
        when Array
          "[" + raw.map { |item| flow(item, true) }.join(", ") + "]"
        when Nil
          nested ? "null" : ""
        when String
          string(raw)
        else
          raw.to_s
        end
      end

      private def scalar_key(key : String) : String
        string(key)
      end

      # Plain when it reads back as the same string; double-quoted otherwise.
      private def string(text : String) : String
        if text.matches?(PLAIN) && YamlTree.plain(text).raw == text
          text
        else
          text.to_json
        end
      end
    end
  end
end
