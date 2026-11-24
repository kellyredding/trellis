module Trellis
  module Commands
    # Commands answered by the app over its socket. `detail_data` for each is
    # built exactly per docs/contract.md, "Events".
    module Live
      extend self

      TARGET_FLAGS = ["--window", "--app", "--title"]

      TARGET_HELP = <<-TEXT
        TARGET is nothing (the focused window), --window ID (a CGWindowID from
        `trellis windows`), or --app NAME|BUNDLE-ID [--title REGEX], which must
        match exactly one window; several matches exit 5 and list them.
        TEXT

      HELP = {
        "status" => <<-TEXT,
          trellis status — the app's version, Accessibility grant, layout mode and config

          Exits 3 when the app is not running.
          TEXT
        "screens" => <<-TEXT,
          trellis screens — the displays, indexed from 1 left to right, then top to bottom

          Frames are global top-left coordinates in points.
          TEXT
        "windows" => <<-TEXT,
          trellis windows [--app X] [--title RE] [--screen N] — list windows

          --app      app name or bundle ID (case-insensitive)
          --title    regular expression matched against the title
          --screen   screen index from `trellis screens`
          TEXT
        "place" => <<-TEXT,
          trellis place NAME [TARGET] [--screen N|east|west]
          trellis place --rect X,Y,W,H [--region R] [TARGET]

          Place a window at a named placement from the app's loaded config, or
          at a rect in fractions of the screen's visible frame (optionally
          inside a named region) without saving it. --screen picks the screen
          by index, or east/west of the window's current one.

          #{TARGET_HELP}
          TEXT
        "screen" => <<-TEXT,
          trellis screen east|west [TARGET] — move a window to the next display

          Keeps its position and size as fractions of the visible frame.

          #{TARGET_HELP}
          TEXT
        "chord" => <<-TEXT,
          trellis chord "KEYS" — run a chord as if typed after the leader

          Runs on the focused window through the app's own resolver.
          An unbound chord runs nothing and exits 0.
          TEXT
        "reload" => <<-TEXT,
          trellis reload — ask the app to reload the config

          Exits 1 when the app could not load it (it keeps the last good one).
          TEXT
      }

      def run(command : String, argv : Array(String)) : Int32
        case command
        when "status"  then status(argv)
        when "screens" then screens(argv)
        when "windows" then windows(argv)
        when "place"   then place(argv)
        when "screen"  then screen_move(argv)
        when "chord"   then chord(argv)
        else                reload(argv)
        end
      end

      private def parse(command : String, argv : Array(String), values = [] of String) : Args?
        args = Args.parse(argv, values: values)
        if args.help?
          STDOUT.puts HELP[command]
          return nil
        end
        args
      end

      private def status(argv : Array(String)) : Int32
        args = parse("status", argv) || return ExitCode::OK
        args.at_most(0)
        data = SocketClient.request("status")
        return print_data(data) if args.json?

        STDOUT.puts "Trellis #{Format.field(data, "version")} (pid #{Format.field(data, "pid")})"
        if (version = data["version"]?.try(&.as_s?)) && version != VERSION
          STDOUT.puts "  note: this CLI is #{VERSION}"
        end
        STDOUT.puts "accessibility  #{data["accessibility"]?.try(&.as_bool?) ? "granted" : "NOT granted"}"
        STDOUT.puts "layout mode    #{data["layout_mode"]?.try(&.as_bool?) ? "on" : "off"}"
        if config = data["config"]?
          STDOUT.puts "config         #{Format.app_config(config, " " * 15)}"
        end
        ExitCode::OK
      end

      private def screens(argv : Array(String)) : Int32
        args = parse("screens", argv) || return ExitCode::OK
        args.at_most(0)
        data = SocketClient.request("screens")
        return print_data(data) if args.json?
        list = data["screens"]?.try(&.as_a?) || [] of JSON::Any
        list.each { |screen| STDOUT.puts Format.screen(screen) }
        ExitCode::OK
      end

      private def windows(argv : Array(String)) : Int32
        args = parse("windows", argv, ["--app", "--title", "--screen"]) || return ExitCode::OK
        args.at_most(0)
        detail = {} of String => JSON::Any
        args["--app"].try { |app| detail["app"] = JSON::Any.new(app) }
        args["--title"].try { |title| detail["title"] = JSON::Any.new(title) }
        args["--screen"].try { |screen| detail["screen"] = JSON::Any.new(screen_index(screen)) }

        data = SocketClient.request("windows", detail.empty? ? nil : detail)
        return print_data(data) if args.json?
        list = data["windows"]?.try(&.as_a?) || [] of JSON::Any
        STDOUT.puts "no windows match" if list.empty?
        list.each { |window| STDOUT.puts Format.window(window) }
        ExitCode::OK
      end

      private def place(argv : Array(String)) : Int32
        args = parse("place", argv, TARGET_FLAGS + ["--rect", "--region", "--screen"]) || return ExitCode::OK
        args.at_most(1)
        name = args.positionals.first?
        rect_text = args["--rect"]

        detail = {} of String => JSON::Any
        target(args).try { |target| detail["target"] = target }
        if name && rect_text
          raise UsageError.new("give a placement name or --rect, not both")
        elsif name
          raise UsageError.new("--region goes with --rect") if args["--region"]
          detail["placement"] = JSON::Any.new(name)
        elsif rect_text
          rect = Support.parse_rect(rect_text)
          detail["rect"] = JSON::Any.new({
            "x" => Support.number(rect.x), "y" => Support.number(rect.y),
            "w" => Support.number(rect.w), "h" => Support.number(rect.h),
          })
          args["--region"].try { |region| detail["region"] = JSON::Any.new(region) }
        else
          raise UsageError.new("expected a placement name or --rect X,Y,W,H")
        end
        if screen = args["--screen"]
          detail["screen"] = screen == "east" || screen == "west" ? JSON::Any.new(screen) : JSON::Any.new(screen_index(screen))
        end

        window_result(args, SocketClient.request("place", detail), "placed")
      end

      private def screen_move(argv : Array(String)) : Int32
        args = parse("screen", argv, TARGET_FLAGS) || return ExitCode::OK
        args.at_most(1)
        direction = args.positional(0, "a direction: east or west")
        unless direction == "east" || direction == "west"
          raise UsageError.new("the direction is east or west, got #{direction.inspect}")
        end

        detail = {} of String => JSON::Any
        target(args).try { |target| detail["target"] = target }
        detail["direction"] = JSON::Any.new(direction)
        window_result(args, SocketClient.request("screen.move", detail), "moved #{direction}")
      end

      private def chord(argv : Array(String)) : Int32
        args = parse("chord", argv) || return ExitCode::OK
        args.at_most(1)
        keys = Keys.canonical_chord(args.positional(0, "a chord, such as \"l l\""))
        data = SocketClient.request("chord", {"keys" => JSON::Any.new(keys)})
        return print_data(data) if args.json?

        target = data["target"]?
        if target.nil? || target.raw.nil?
          STDOUT.puts "#{keys} is not bound; nothing ran"
        else
          name = Format.field(target, "placement")
          name = "#{Format.field(target, "action")} (action)" if name == "?"
          STDOUT.puts "#{keys} -> #{name}#{data["ran"]?.try(&.as_bool?) ? "" : " (did not run)"}"
        end
        ExitCode::OK
      end

      private def reload(argv : Array(String)) : Int32
        args = parse("reload", argv) || return ExitCode::OK
        args.at_most(0)
        data = SocketClient.request("config.reload")
        loaded = data["loaded"]?.try(&.as_bool?) || false
        if args.json?
          print_data(data)
        elsif loaded
          STDOUT.puts "Trellis reloaded the config"
        end
        unless loaded
          raise Error.new("Trellis could not load the config (keeping the last good one): " \
                          "#{data["error"]?.try(&.as_s?) || "no reason given"}")
        end
        ExitCode::OK
      end

      private def target(args : Args) : JSON::Any?
        window = args["--window"]
        app = args["--app"]
        title = args["--title"]
        if window
          raise UsageError.new("--window cannot be combined with --app or --title") if app || title
          id = window.to_i64? || raise UsageError.new("--window needs a window ID, got #{window.inspect}")
          JSON::Any.new({"window_id" => JSON::Any.new(id)})
        elsif app
          object = {"app" => JSON::Any.new(app)}
          object["title"] = JSON::Any.new(title) if title
          JSON::Any.new(object)
        elsif title
          raise UsageError.new("--title goes with --app")
        end
      end

      private def screen_index(text : String) : Int64
        index = text.to_i64?
        raise UsageError.new("--screen needs a screen index from 1, got #{text.inspect}") unless index && index >= 1
        index
      end

      private def window_result(args : Args, data : JSON::Any, verb : String) : Int32
        return print_data(data) if args.json?
        window = data["window"]?
        STDOUT.puts window ? "#{verb}: #{Format.window(window)}" : verb
        ExitCode::OK
      end

      private def print_data(data : JSON::Any) : Int32
        Support.print_json(data)
        ExitCode::OK
      end
    end
  end
end
