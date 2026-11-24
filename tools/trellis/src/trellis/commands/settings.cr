module Trellis
  module Commands
    # Reached as `trellis settings`; named so `Config::Settings` stays
    # unambiguous.
    module SettingsCommand
      extend self

      KEYS = ["leader", "chord_wait_ms", "label.screens", "label.corner", "cheat_sheet", "dropdown.screens"]

      HELP = <<-TEXT
        trellis settings list | get KEY | set KEY VALUE

        Keys:
          leader             The key that enters layout mode, with at least one
                             modifier (default ctrl+s)
          chord_wait_ms      How long a chord that starts a longer one waits,
                             50 to 2000 (default 400)
          label.screens      Where the layout-mode label shows: all, main, target
          label.corner       top-left, top-right, bottom-left, bottom-right
          cheat_sheet        off, label, dropdown
          dropdown.screens   off, all, main

        set validates the whole config and rewrites the file (see
        `trellis config --help`).
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv)
        Support.help(args, HELP).try { |code| return code }
        case action = args.positional(0, "an action: list, get or set")
        when "list" then list(args)
        when "get"  then get(args)
        when "set"  then set(args)
        else
          raise UsageError.new("unknown settings action #{action.inspect}")
        end
      end

      def value(settings : Config::Settings, key : String) : String | Int64
        case key
        when "leader"        then settings.leader
        when "chord_wait_ms" then settings.chord_wait_ms
        when "label.screens" then settings.label_screens
        when "label.corner"  then settings.label_corner
        when "cheat_sheet"   then settings.cheat_sheet
        else                      settings.dropdown_screens
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        loaded = Config::Store.load
        model = loaded.model
        tree = loaded.tree
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("settings") do
                json.object { KEYS.each { |key| json.field key, value(model.settings, key) } }
              end
              json.field "explicit", KEYS.select { |key| explicit?(tree, key) }
            end
          end
        else
          rows = KEYS.map do |key|
            [key, value(model.settings, key).to_s, explicit?(tree, key) ? "" : "(default)"]
          end
          STDOUT.puts Format.table(rows)
        end
        ExitCode::OK
      end

      private def get(args : Args) : Int32
        args.at_most(2)
        key = known_key(args.positional(1, "a setting key"))
        current = value(Config::Store.model.settings, key)
        if args.json?
          Support.print_json({"key" => key, "value" => current})
        else
          STDOUT.puts current
        end
        ExitCode::OK
      end

      private def set(args : Args) : Int32
        args.at_most(3)
        key = known_key(args.positional(1, "a setting key"))
        raw = args.positional(2, "a value")
        typed = case key
                when "chord_wait_ms"
                  JSON::Any.new(raw.to_i64? || raise Error.new("chord_wait_ms must be a whole number, got #{raw.inspect}"))
                when "leader"
                  JSON::Any.new(Keys.canonical_token(raw))
                else
                  JSON::Any.new(raw)
                end

        outcome = Config::Mutation.apply do |mutation|
          hash = mutation.section("settings")
          parts = key.split('.')
          parts[0...-1].each do |part|
            child = hash[part]?.try(&.as_h?) || {} of String => JSON::Any
            hash[part] = JSON::Any.new(child)
            hash = child
          end
          hash[parts.last] = typed
        end

        updated = value(outcome.model.settings, key)
        Support.report_mutation(args, outcome, "#{key} = #{updated}") do |json|
          json.field "key", key
          json.field "value", updated
        end
      end

      private def known_key(key : String) : String
        return key if KEYS.includes?(key)
        raise UsageError.new("unknown setting #{key.inspect}; settings are #{KEYS.join(", ")}")
      end

      private def explicit?(tree : JSON::Any, key : String) : Bool
        node = tree
        (["settings"] + key.split('.')).each do |part|
          node = node.as_h?.try(&.[part]?) || return false
        end
        !node.raw.nil?
      end
    end
  end
end
