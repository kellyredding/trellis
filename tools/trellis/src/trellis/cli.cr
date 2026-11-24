module Trellis
  module CLI
    extend self

    USAGE = <<-TEXT
      trellis — keyboard window layout for macOS

      Usage: trellis <command> [options]      (every command takes --json)

      Live (talk to the Trellis app):
        status                          App version, Accessibility, layout mode, config
        screens                         Displays, indexed from 1 left to right
        windows [--app X] [--title RE] [--screen N]
        place NAME [TARGET] [--screen N|east|west]
        place --rect X,Y,W,H [--region R] [TARGET]
        screen east|west [TARGET]       Move a window to the next display
        chord "KEYS"                    Run a chord as if typed after the leader
        reload                          Ask the app to reload the config

        TARGET is nothing (the focused window), --window ID, or
        --app NAME|BUNDLE-ID [--title REGEX] matching exactly one window.

      Config (no app needed):
        config path|show|validate|export --json|init [--starter] [--force]
        groups list|add|rename|remove|move
        placements list|show|add|set|rename|remove
        actions list|set                The built-in actions and their groups
        regions list|show|add|set|remove
        bindings list|show CHORD
        bind CHORD TARGET               Bind a chord to a placement or action
        unbind CHORD
        resolve CHORD                   What a chord runs, and whether it waits
        settings list|get KEY|set KEY VALUE

      Health:
        doctor                          Check the CLI, the config and the app
        version                         Print the version
        update                          Install the latest release

      Exit codes: 0 ok, 1 failed, 2 usage, 3 app not running,
      4 Accessibility not granted, 5 window or screen not found or ambiguous.

      Run `trellis <command> --help` for a command's options.
      TEXT

    def run(argv : Array(String)) : NoReturn
      exit(dispatch(argv))
    end

    def dispatch(argv : Array(String)) : Int32
      json = argv.includes?("--json")
      command = argv.first?
      rest = argv.size > 1 ? argv[1..] : [] of String

      guard(json) do
        case command
        when nil
          STDERR.puts USAGE
          ExitCode::USAGE
        when "help", "--help", "-h"
          STDOUT.puts USAGE
          ExitCode::OK
        when "version", "--version", "-V"
          Commands::Version.run(rest)
        when "update"
          Commands::Update.run(rest)
        when "doctor"
          Commands::Doctor.run(rest)
        when "status", "screens", "windows", "place", "screen", "chord", "reload"
          Commands::Live.run(command, rest)
        when "config"
          Commands::ConfigFile.run(rest)
        when "groups"
          Commands::Groups.run(rest)
        when "placements"
          Commands::Placements.run(rest)
        when "actions"
          Commands::Actions.run(rest)
        when "regions"
          Commands::Regions.run(rest)
        when "bindings", "bind", "unbind"
          Commands::Bindings.run(command, rest)
        when "resolve"
          Commands::Resolve.run(rest)
        when "settings"
          Commands::SettingsCommand.run(rest)
        else
          raise UsageError.new("unknown command #{command.inspect}")
        end
      end
    end

    # Every anticipated failure becomes a message on stderr and its exit code;
    # with --json the same failure is also printed as a JSON object on stdout.
    def guard(json : Bool, &) : Int32
      yield
    rescue error : Trellis::Error
      STDERR.puts "trellis: #{error.message}"
      error.details.each { |line| STDERR.puts line }
      STDERR.puts "Run `trellis --help` for usage." if error.is_a?(UsageError)
      STDOUT.puts error.to_pretty_json if json
      error.exit_code
    end
  end
end
