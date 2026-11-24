module Trellis
  module Commands
    # Reached as `trellis config`. Named ConfigFile so `Config` keeps meaning
    # the config library in every sibling command.
    module ConfigFile
      extend self

      HELP = <<-TEXT
        trellis config — the config file

        Actions:
          path                     The configured path (and where its symlink resolves)
          show                     The config file's JSON (the built-in starter when no file exists)
          validate                 Check it: errors exit 1; prefix chords are warnings
          export --json            The normalized config the app loads
          init [--starter] [--force]
                                   Write a config file: a minimal one, or the starter
                                   set with --starter. Refuses to replace an existing
                                   file without --force.

        The config is a JSON file at $TRELLIS_CONFIG, or
        $TRELLIS_ROOT/config.json (default ~/.trellis/config.json), and may be
        a symlink: writes replace the file it points to, never the link.

        Commands that change the config (bind, unbind, groups, placements,
        actions, regions, settings set) validate the whole result and refuse an invalid one. They
        rewrite the file with its sections in canonical order and every other
        key where it was. After editing the file by hand, run
        `trellis config validate`.
        TEXT

      MINIMAL = <<-JSON
        {
          "version": 1,
          "groups": ["Full screen"],
          "placements": {
            "maximize": {
              "rect": [0, 0, 1, 1],
              "group": "Full screen"
            }
          },
          "bindings": {
            "return": "maximize"
          }
        }

        JSON

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, switches: ["--starter", "--force"])
        Support.help(args, HELP).try { |code| return code }
        action = args.positional(0, "an action: path, show, validate, export or init")
        args.at_most(1)
        if action != "init" && (args.switch?("--starter") || args.switch?("--force"))
          raise UsageError.new("--starter and --force go with init")
        end

        case action
        when "path"     then path(args)
        when "show"     then show(args)
        when "validate" then validate(args)
        when "export"   then export
        when "init"     then init(args)
        else
          raise UsageError.new("unknown config action #{action.inspect}")
        end
      end

      private def path(args : Args) : Int32
        path = Paths.config_file
        exists = File.exists?(path.to_s)
        resolved = File.symlink?(path.to_s) ? Config::Writer.resolve(path) : nil
        if args.json?
          Support.print_json({
            "path"     => path.to_s,
            "resolved" => resolved.try(&.to_s),
            "exists"   => exists,
            "source"   => exists ? "file" : "starter",
          })
        else
          STDOUT.puts path
          STDOUT.puts "  -> #{resolved}" if resolved
          STDOUT.puts "  (no file: the built-in starter is in use)" unless exists
        end
        ExitCode::OK
      end

      private def show(args : Args) : Int32
        loaded = Config::Store.load
        if args.json?
          STDOUT.puts Config::Export.to_json(loaded.model)
        else
          STDERR.puts "no config file at #{loaded.path}; this is the built-in starter" if loaded.source.starter?
          STDOUT.print loaded.text
        end
        ExitCode::OK
      end

      private def validate(args : Args) : Int32
        loaded = Config::Store.load
        result = begin
          loaded.validate
        rescue error : InvalidConfig
          Config::Result.new(nil, error.errors, [] of String)
        end

        if args.json?
          Support.print_json({
            "valid"    => result.valid?,
            "path"     => loaded.path.to_s,
            "source"   => loaded.source.label,
            "errors"   => result.errors,
            "warnings" => result.warnings,
          })
        elsif result.valid?
          STDOUT.puts "valid: #{loaded.path}#{loaded.source.starter? ? " (built-in starter)" : ""}"
          result.warnings.each { |warning| STDOUT.puts "warning: #{warning}" }
        else
          STDERR.puts "invalid: #{loaded.path}"
          result.errors.each { |error| STDERR.puts "  #{error}" }
        end
        result.valid? ? ExitCode::OK : ExitCode::FAILED
      end

      # JSON only: it exists for the app and for agents.
      private def export : Int32
        STDOUT.puts Config::Export.to_json(Config::Store.model)
        ExitCode::OK
      end

      private def init(args : Args) : Int32
        path = Paths.config_file
        if File.exists?(path.to_s) && !args.switch?("--force")
          raise Error.new("#{path} already exists; pass --force to replace it")
        end
        text = args.switch?("--starter") ? STARTER_CONFIG : MINIMAL
        written = Config::Writer.write(path, text)
        reload = SocketClient.reload_quietly
        kind = args.switch?("--starter") ? "the starter config" : "a minimal config"

        if args.json?
          Support.print_json do |json|
            json.object do
              json.field "ok", true
              json.field "path", path.to_s
              json.field "written", written.to_s
              json.field "reload", reload
            end
          end
        else
          STDOUT.puts "wrote #{kind} to #{path}"
          STDOUT.puts "  wrote #{written}" if written != path.expand
          STDOUT.puts "  #{reload.summary}"
        end
        ExitCode::OK
      end
    end
  end
end
