module Trellis
  module Config
    # Replaces the config file atomically without ever replacing a symlink:
    # the link is resolved, a temp file is written beside the real file, and
    # the temp file is renamed over the real one. Renaming over the link path
    # would turn the link into a regular file and detach it from its target.
    module Writer
      extend self

      MAX_LINKS = 32

      # Writes `text` to the file `path` names and returns the real path.
      def write(path : Path, text : String) : Path
        real = resolve(path)
        temp = real.parent / ".#{real.basename}.#{Process.pid}.#{Random::Secure.hex(4)}.tmp"
        begin
          Dir.mkdir_p(real.parent.to_s)
          File.write(temp.to_s, text)
          if File.exists?(real.to_s)
            File.chmod(temp.to_s, File.info(real.to_s).permissions)
          end
          File.rename(temp.to_s, real.to_s)
        rescue error : File::Error
          File.delete?(temp.to_s) rescue nil
          raise Error.new("could not write #{real}: #{error.message}")
        end
        real
      end

      # Follows a chain of symlinks, dangling or not, to the file a write
      # should replace.
      def resolve(path : Path) : Path
        current = path.expand
        MAX_LINKS.times do
          return current unless File.symlink?(current.to_s)
          # The kernel resolves a relative target from the link's real
          # directory; a lexical `..` would go wrong under a symlinked parent.
          current = Path.new(File.readlink(current.to_s)).expand(File.realpath(current.parent.to_s))
        end
        raise Error.new("#{path} is a symlink loop")
      end
    end
  end
end
