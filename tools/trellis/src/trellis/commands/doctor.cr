require "digest/sha256"

module Trellis
  module Commands
    # Independent checks, all reported rather than stopping at the first.
    # The app being down is reported, never a failure on its own.
    module Doctor
      extend self

      HELP = <<-TEXT
        trellis doctor — check the CLI, the config and the app

        Reports the CLI version; the install record install.sh leaves at
        ~/.trellis/installed-manifest.json (version, commit, build time, signer)
        and, when there is one, whether ~/Applications/Trellis.app is that build
        and signed by that signer, whether ~/.trellis/bin/trellis is that build,
        and which Trellis.app copies Launch Services knows; the config path, where its symlink resolves, whether it is a file or the
        built-in starter, and whether it is valid JSON and a valid config; and
        whether the app answers, its version, its Accessibility grant and
        whether its last config reload worked.
        Exits 1 when a check fails. No install record, a registration problem,
        the app not running, or the app keeping its last good config after a
        failed reload, is a warning.
        TEXT

      LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Versions/" \
                   "Current/Frameworks/LaunchServices.framework/Versions/Current/" \
                   "Support/lsregister"

      enum Level
        Ok
        Warn
        Fail

        def marker : String
          case self
          in .ok?   then "ok  "
          in .warn? then "warn"
          in .fail? then "FAIL"
          end
        end
      end

      record Check, level : Level, name : String, detail : String do
        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "level", level.to_s.downcase
            json.field "name", name
            json.field "detail", detail
          end
        end
      end

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv)
        Support.help(args, HELP).try { |code| return code }
        args.at_most(0)

        checks = [Check.new(Level::Ok, "cli", "trellis #{VERSION}")]
        install = install_checks(checks)
        config = config_checks(checks)
        app = app_checks(checks)

        if args.json?
          Support.print_json do |json|
            json.object do
              json.field "ok", checks.none?(&.level.fail?)
              json.field("cli") { json.object { json.field "version", VERSION } }
              json.field("install") { install.call(json) }
              json.field("config") { config.call(json) }
              json.field("app") { app.call(json) }
              json.field "checks", checks
            end
          end
        else
          width = checks.max_of(&.name.size)
          checks.each do |check|
            STDOUT.puts "#{check.level.marker}  #{check.name.ljust(width)}  #{check.detail}"
          end
        end

        checks.any?(&.level.fail?) ? ExitCode::FAILED : ExitCode::OK
      end

      def installed_manifest : Path
        Paths.root / "installed-manifest.json"
      end

      # Overridable for specs only, as kx's doctor is.
      def installed_app : Path
        dir = ENV["TRELLIS_APPLICATIONS_DIR"]?
        (dir && !dir.empty? ? Path.new(dir) : Path.home / "Applications") / "Trellis.app"
      end

      def lsregister : String
        ENV["TRELLIS_LSREGISTER"]?.try { |path| path unless path.empty? } || LSREGISTER
      end

      # The manifest install.sh copied out of the archive it installed.
      private def install_checks(checks : Array(Check)) : Proc(JSON::Builder, Nil)
        path = installed_manifest
        manifest = read_manifest(path)
        app = nil
        cli = nil
        registered = nil
        if manifest
          checks << Check.new(Level::Ok, "install", describe_install(manifest))
          app = installed_app_checks(checks, manifest)
          cli = installed_cli_check(checks, manifest)
          registered = registration_checks(checks)
        else
          problem = File.exists?(path) ? "unreadable install record at #{path}" : "no install record at #{path}"
          checks << Check.new(Level::Warn, "install", "#{problem}; `trellis update` installs a release and writes one")
        end

        ->(json : JSON::Builder) do
          json.object do
            json.field "manifest_path", path.to_s
            json.field "manifest", manifest
            json.field "app", app
            json.field "cli", cli
            json.field "registered", registered
          end
          nil
        end
      end

      private def installed_app_checks(checks : Array(Check), manifest : JSON::Any) : Hash(String, String?)?
        app = installed_app
        if File.symlink?(app)
          target = File.realpath(app) rescue "nothing"
          checks << Check.new(Level::Fail, "installed app", "#{app} is a link to #{target}, not an installed copy; `trellis update` installs one")
          return nil
        end
        unless Dir.exists?(app)
          checks << Check.new(Level::Fail, "installed app", "#{app} is missing; `trellis update` installs it")
          return nil
        end

        version = plist_value(app, "CFBundleShortVersionString")
        commit = plist_value(app, "TrellisBuildCommit")
        recorded = manifest["commit"]?.try(&.as_s?)
        if commit.nil?
          checks << Check.new(Level::Fail, "installed app", "Trellis.app carries no build commit, so install.sh did not install it; `trellis update` replaces it")
        elsif recorded && commit != recorded
          checks << Check.new(Level::Fail, "installed app", "Trellis.app is from #{commit}, the install record from #{recorded}; `trellis update` reinstalls both")
        else
          checks << Check.new(Level::Ok, "installed app", "Trellis.app #{version || "unknown version"} (#{commit})")
        end

        signer = signing_authority(app)
        expected = manifest["signer"]?.try(&.as_s?)
        if signer.nil?
          checks << Check.new(Level::Fail, "app signer", "Trellis.app is ad hoc or unsigned, so macOS will not keep its Accessibility permission")
        elsif expected && signer != expected
          checks << Check.new(Level::Fail, "app signer", "Trellis.app is signed by #{signer}, the install record says #{expected}")
        else
          checks << Check.new(Level::Ok, "app signer", "Trellis.app signed by #{signer}")
        end

        {"path" => app.to_s, "version" => version, "commit" => commit, "signer" => signer}
      end

      private def installed_cli_check(checks : Array(Check), manifest : JSON::Any) : Hash(String, String | Bool | Nil)
        binary = Paths.binary
        expected = manifest["trellis_sha256"]?.try(&.as_s?)
        sha256 = File.file?(binary) ? Digest::SHA256.new.file(binary.to_s).hexfinal : nil
        if sha256.nil?
          checks << Check.new(Level::Fail, "installed cli", "#{binary} is missing; `trellis update` installs it")
        elsif expected.nil?
          checks << Check.new(Level::Warn, "installed cli", "the install record has no checksum to compare #{binary} with")
        elsif sha256 == expected
          checks << Check.new(Level::Ok, "installed cli", "#{binary} is the recorded build")
        else
          checks << Check.new(Level::Fail, "installed cli", "#{binary} is not the build the install record names; `trellis update` reinstalls it")
        end
        {"path" => binary.to_s, "sha256" => sha256, "matches" => !sha256.nil? && sha256 == expected}
      end

      # Trellis registers no URL scheme, so a stray copy only confuses
      # Spotlight and `open -a`: a warning, not a failure.
      private def registration_checks(checks : Array(Check)) : Array(String)?
        output = IO::Memory.new
        status = Process.run(lsregister, ["-dump"], output: output, error: Process::Redirect::Close)
        unless status.success?
          checks << Check.new(Level::Warn, "registration", "could not ask Launch Services (lsregister exited #{status.exit_code? || "on a signal"})")
          return nil
        end
        paths = output.to_s.lines.compact_map do |line|
          line.match(/^path:\s+(.*\/Trellis\.app) \(0x[0-9a-f]+\)$/).try(&.[1])
        end.uniq

        app = installed_app.to_s
        if paths.includes?(app)
          checks << Check.new(Level::Ok, "registration", "Launch Services knows #{app}")
        else
          checks << Check.new(Level::Warn, "registration", "Launch Services does not know #{app}; `trellis update` registers it")
        end
        paths.reject(app).each do |other|
          checks << Check.new(Level::Warn, "registration", "another Trellis.app is registered: #{other}")
        end
        paths
      rescue error : File::Error
        checks << Check.new(Level::Warn, "registration", "could not ask Launch Services: #{error.message}")
        nil
      end

      private def plist_value(app : Path, key : String) : String?
        output = IO::Memory.new
        status = Process.run("/usr/libexec/PlistBuddy", ["-c", "Print :#{key}", (app / "Contents" / "Info.plist").to_s],
          output: output, error: Process::Redirect::Close)
        status.success? ? output.to_s.strip : nil
      end

      private def signing_authority(app : Path) : String?
        output = IO::Memory.new
        Process.run("codesign", ["-dv", "--verbose=2", app.to_s], output: output, error: output)
        output.to_s.each_line.find(&.starts_with?("Authority=")).try(&.lchop("Authority="))
      end

      private def read_manifest(path : Path) : JSON::Any?
        return nil unless File.file?(path)
        manifest = JSON.parse(File.read(path))
        manifest.as_h? ? manifest : nil
      rescue JSON::ParseException | File::Error
        nil
      end

      private def describe_install(manifest : JSON::Any) : String
        field = ->(name : String) { manifest[name]?.try(&.as_s?) }
        build = [field.call("commit") || "unknown commit"]
        build << "uncommitted changes" if manifest["dirty"]?.try(&.as_bool?)
        detail = "Trellis #{field.call("version") || "unknown"} (#{build.join(", ")})"
        field.call("built_at").try { |built| detail += ", built #{built}" }
        signer = field.call("signer")
        detail += signer ? ", signed by #{signer}" : ", signer not recorded"
        detail
      end

      private def config_checks(checks : Array(Check)) : Proc(JSON::Builder, Nil)
        path = Paths.config_file
        resolved = nil
        source = nil
        errors = [] of String
        warnings = [] of String

        begin
          loaded = Config::Store.load(path)
          source = loaded.source
          resolved = loaded.resolved_path
          detail = path.to_s
          detail += " -> #{resolved}" if resolved && resolved != path.expand
          detail += " (missing: using the built-in starter)" if source.starter?
          checks << Check.new(Level::Ok, "config path", detail)

          result = loaded.validate
          errors = result.errors
          warnings = result.warnings
          if model = result.model
            checks << Check.new(Level::Ok, "config", "valid: #{model.placements.size} placements, #{model.bindings.size} bindings")
          else
            checks << Check.new(Level::Fail, "config", "invalid: #{errors.join("; ")}")
          end
          warnings.each { |warning| checks << Check.new(Level::Warn, "config", warning) }
        rescue error : InvalidConfig
          errors = error.errors
          checks << Check.new(Level::Fail, "config", "invalid: #{errors.join("; ")}")
        rescue error : Error
          errors = [error.message || "unreadable"]
          checks << Check.new(Level::Fail, "config path", errors.first)
        end

        ->(json : JSON::Builder) do
          json.object do
            json.field "path", path.to_s
            json.field "resolved", resolved.try(&.to_s)
            json.field "source", source.try(&.label)
            json.field "valid", errors.empty?
            json.field "errors", errors
            json.field "warnings", warnings
          end
          nil
        end
      end

      private def app_checks(checks : Array(Check)) : Proc(JSON::Builder, Nil)
        status = SocketClient.request("status")
        version = status["version"]?.try(&.as_s?)
        if version == VERSION
          checks << Check.new(Level::Ok, "app", "running, version #{version}")
        else
          checks << Check.new(Level::Warn, "app", "running, version #{version || "unknown"}; this CLI is #{VERSION}")
        end

        if status["accessibility"]?.try(&.as_bool?)
          checks << Check.new(Level::Ok, "accessibility", "granted")
        else
          checks << Check.new(Level::Fail, "accessibility", "not granted: System Settings > Privacy & Security > Accessibility")
        end

        app_config = status["config"]?
        if app_config && app_config["loaded"]?.try(&.as_bool?)
          if error = app_config["error"]?.try(&.as_s?)
            checks << Check.new(Level::Warn, "app config",
              "keeping the last good config; the last reload failed: #{error.lines.map(&.strip).reject(&.empty?).join("; ")}")
          else
            checks << Check.new(Level::Ok, "app config", "loaded")
          end
        else
          checks << Check.new(Level::Warn, "app config", app_config.try { |config| Format.app_config(config) } || "not reported")
        end

        ->(json : JSON::Builder) do
          json.object do
            json.field "running", true
            json.field "status", status
          end
          nil
        end
      rescue down : SocketClient::NotRunning
        reason = down.message
        checks << Check.new(Level::Warn, "app", "not running")
        ->(json : JSON::Builder) do
          json.object do
            json.field "running", false
            json.field "reason", reason
          end
          nil
        end
      rescue failure : Error
        message = failure.message
        checks << Check.new(Level::Fail, "app", message || "did not answer")
        ->(json : JSON::Builder) do
          json.object do
            json.field "running", true
            json.field "error", message
          end
          nil
        end
      end
    end
  end
end
