module Trellis
  module Config
    # The config as read from disk: the file at the configured path, or the
    # embedded starter when there is none.
    record Loaded, path : Path, source : Source, text : String do
      def tree : JSON::Any
        Reader.parse(text)
      end

      def validate : Result
        Validator.validate(tree, source, path)
      end

      def model : Model
        validate.model!
      end

      def resolved_path : Path?
        source.file? ? Writer.resolve(path) : nil
      end
    end

    module Store
      extend self

      def load(path : Path = Paths.config_file) : Loaded
        if File.exists?(path.to_s)
          Loaded.new(path, Source::File, File.read(path.to_s))
        elsif File.symlink?(path.to_s)
          raise Error.new("#{path} is a symlink to #{Writer.resolve(path)}, which does not exist")
        else
          Loaded.new(path, Source::Starter, STARTER_CONFIG)
        end
      end

      def model(path : Path = Paths.config_file) : Model
        load(path).model
      end
    end
  end
end
