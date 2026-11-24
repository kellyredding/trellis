module Trellis
  module Commands
    # Independent checks, all reported rather than stopping at the first.
    # The app being down is reported, never a failure on its own.
    module Doctor
      extend self

      HELP = <<-TEXT
        trellis doctor — check the CLI, the config and the app

        Reports the CLI version; the config path, where its symlink resolves,
        whether it is a file or the built-in starter, and whether it is valid
        JSON and a valid config;
        and whether the app answers, its version and its Accessibility grant.
        Exits 1 when a check fails. The app not running is a warning.
        TEXT

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
        config = config_checks(checks)
        app = app_checks(checks)

        if args.json?
          Support.print_json do |json|
            json.object do
              json.field "ok", checks.none?(&.level.fail?)
              json.field("cli") { json.object { json.field "version", VERSION } }
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
          checks << Check.new(Level::Ok, "app config", "loaded")
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
