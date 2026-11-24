module Trellis
  module Config
    # One change to the config: load (the starter when there is no file),
    # apply, validate the whole result, write symlink-safely, then ask the app
    # to reload. An invalid result is refused and nothing is written.
    class Mutation
      record Outcome,
        path : Path,
        written : Path,
        model : Model,
        reload : SocketClient::ReloadOutcome

      getter root : Hash(String, JSON::Any)

      def self.apply(&block : Mutation -> Nil) : Outcome
        mutation = new(Store.load)
        yield mutation
        mutation.commit
      end

      def initialize(@loaded : Loaded)
        tree = @loaded.tree
        if tree.raw.nil?
          @root = {} of String => JSON::Any
        else
          @root = tree.as_h? || raise InvalidConfig.new("the config is invalid", ["the config: must be an object"])
        end
      end

      # The named section's object, created in canonical position if absent.
      def section(name : String) : Hash(String, JSON::Any)
        existing = @root[name]?
        if existing && !existing.raw.nil?
          return existing.as_h? || raise InvalidConfig.new(
            "the config is invalid", ["#{name}: must be an object"])
        end

        hash = {} of String => JSON::Any
        insert_section(name, JSON::Any.new(hash))
        hash
      end

      def section?(name : String) : Hash(String, JSON::Any)?
        @root[name]?.try(&.as_h?)
      end

      def commit : Outcome
        result = Validator.validate(JSON::Any.new(@root), @loaded.source, @loaded.path)
        unless result.valid?
          raise InvalidConfig.new("refused: the change would leave the config invalid; nothing was written", result.errors)
        end

        written = Writer.write(@loaded.path, Emitter.emit(@root))
        model = result.model!
        Outcome.new(@loaded.path, written, model.copy_with(source: Source::File), SocketClient.reload_quietly)
      end

      # Replaces a key in place, keeping its position.
      def self.rename_key(hash : Hash(String, JSON::Any), from : String, to : String) : Nil
        entries = hash.to_a
        hash.clear
        entries.each { |key, value| hash[key == from ? to : key] = value }
      end

      private def insert_section(name : String, value : JSON::Any) : Nil
        order = SECTIONS.index(name) || SECTIONS.size
        entries = @root.to_a
        position = entries.index { |key, _| (SECTIONS.index(key) || SECTIONS.size) > order } || entries.size
        entries.insert(position, {name, value})
        @root.clear
        entries.each { |key, item| @root[key] = item }
      end
    end
  end
end
