require "file_utils"

module Trellis
  module Commands
    module Update
      extend self

      INSTALL_SCRIPT_URL = "https://raw.githubusercontent.com/kellyredding/trellis/main/install.sh"
      ARCHIVE            = "trellis-darwin.tar.gz"
      SWITCHES           = ["--local", "--preview", "--force"]

      HELP = <<-TEXT
        trellis update — install the latest release, or a Trellis checkout

        Usage:
          trellis update                   Install the latest release
          trellis update --version X.Y.Z   Install that release
          trellis update --local [PATH]    Package and install a Trellis checkout
                                           (PATH, else the repository you are in),
                                           uncommitted changes included

        Options:
          --preview   Show what would change, and change nothing
          --force     Reinstall a release even when it is already installed

        Replaces ~/.trellis/bin/trellis and ~/Applications/Trellis.app. A running
        Trellis keeps the old build until you restart it; update never restarts it.

        Releases install through #{INSTALL_SCRIPT_URL}
        --local runs the checkout's bin/package, which signs with the "Trellis
        Release Signing" identity from 1Password and may ask you to approve it.
        Exits with the installer's or the packager's exit code when either fails.
        TEXT

      record Options,
        local : Bool = false,
        local_path : String? = nil,
        version : String? = nil,
        preview : Bool = false,
        force : Bool = false

      def run(argv : Array(String)) : Int32
        args = arguments(argv)
        Support.help(args, HELP).try { |code| return code }
        options = options(args)
        options.local ? run_local(options) : run_release(options)
      end

      def parse(argv : Array(String)) : Options
        options(arguments(argv))
      end

      # Flags for install.sh, in its own spelling.
      def install_args(options : Options) : Array(String)
        args = [] of String
        options.version.try { |version| args.concat(["--version", version]) }
        args << "--preview" if options.preview
        args << "--force" if options.force
        args
      end

      # The checkout to package: PATH, else the git root of the working
      # directory. Nil when that is not a Trellis checkout.
      def resolve_repo(path : String?, cwd : String = Dir.current) : Path?
        start = path ? File.expand_path(path, cwd, home: true) : cwd
        return nil unless Dir.exists?(start)

        output = IO::Memory.new
        status = Process.run("git", ["-C", start, "rev-parse", "--show-toplevel"],
          output: output, error: Process::Redirect::Close)
        return nil unless status.success?

        root = Path.new(output.to_s.strip)
        trellis_repo?(root) ? root : nil
      rescue File::Error
        nil
      end

      # Galaxy's checkout has a bin/package and an install.sh too, so those
      # alone would let --local install Galaxy's archive.
      def trellis_repo?(root : Path) : Bool
        File.file?(root / "bin" / "package") && File.file?(root / "install.sh") &&
          File.file?(root / "TrellisApp" / "project.yml")
      end

      private def arguments(argv : Array(String)) : Args
        Args.parse(argv, values: ["--version"], switches: SWITCHES)
      end

      private def options(args : Args) : Options
        if args.json?
          raise UsageError.new("update prints the installer's progress; it has no --json output")
        end
        args.at_most(1)
        local = args.switch?("--local")
        path = args.positionals.first?
        if path && !local
          raise UsageError.new("unexpected argument #{path.inspect}; a checkout path goes with --local")
        end

        version = args["--version"].try do |raw|
          bare = raw.lchop('v')
          unless bare.matches?(/\A\d+\.\d+\.\d+\z/)
            raise UsageError.new("--version needs a version like 0.1.0, got #{raw.inspect}")
          end
          bare
        end
        if local && version
          raise UsageError.new("--local packages a checkout; it cannot be combined with --version")
        end

        Options.new(local: local, local_path: path, version: version,
          preview: args.switch?("--preview"), force: args.switch?("--force"))
      end

      # The script is fetched before bash runs it: piped straight into bash, a
      # failed download is an empty script, which bash runs and exits 0.
      private def run_release(options : Options) : Int32
        script = IO::Memory.new
        fetched = execute("curl", ["-fsSL", INSTALL_SCRIPT_URL], output: script)
        unless fetched.success?
          raise Error.new("could not download the installer from #{INSTALL_SCRIPT_URL} (#{describe(fetched)})")
        end
        script.rewind
        Support.exit_code_for(execute("bash", ["-s", "--"] + install_args(options), input: script))
      end

      private def run_local(options : Options) : Int32
        repo = resolve_repo(options.local_path)
        unless repo
          where = options.local_path || Dir.current
          raise Error.new("#{where} is not inside a Trellis checkout (no bin/package, install.sh and TrellisApp/project.yml)")
        end

        out_dir = Path.new(File.tempname("trellis-local-", nil))
        begin
          packaged = execute((repo / "bin" / "package").to_s, ["--local", "--out", out_dir.to_s])
          return Support.exit_code_for(packaged) unless packaged.success?

          archive = out_dir / ARCHIVE
          raise Error.new("bin/package wrote no #{ARCHIVE} in #{out_dir}") unless File.file?(archive)
          installer = ["--from", archive.to_s] + install_args(options)
          Support.exit_code_for(execute("bash", [(repo / "install.sh").to_s] + installer))
        ensure
          FileUtils.rm_rf(out_dir.to_s)
        end
      end

      private def execute(command : String, args : Array(String),
                          input : Process::Stdio = Process::Redirect::Inherit,
                          output : Process::Stdio = Process::Redirect::Inherit) : Process::Status
        Process.run(command, args, input: input, output: output, error: Process::Redirect::Inherit)
      rescue error : File::Error
        raise Error.new("could not run #{command}: #{error.message}")
      end

      private def describe(status : Process::Status) : String
        if code = status.exit_code?
          "exit #{code}"
        elsif signal = status.exit_signal?
          "signal #{signal}"
        else
          status.to_s
        end
      end
    end
  end
end
