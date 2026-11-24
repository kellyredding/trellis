module Trellis
  module Commands
    # Reached as `trellis settings`; named so `Config::Settings` stays
    # unambiguous.
    module SettingsCommand
      extend self

      KEYS = ["leader", "chord_wait_ms", "label.screens", "label.corner", "label.linger_ms", "cheat_sheet", "dropdown.screens"]

      HELP = <<-TEXT
        trellis settings list | get KEY | set KEY VALUE

        Keys:
          leader             The key that enters layout mode, with at least one
                             modifier (default ctrl+s)
          chord_wait_ms      How long a chord that starts a longer one waits,
                             50 to 2000 (default 400)
          label.screens      Where the layout-mode label shows: all, main, target
          label.corner       top-left, top-right, bottom-left, bottom-right
          label.linger_ms    How long the label shows a typed chord's result,
                             0 (off) to 3000 (default 2000)
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
        when "leader"          then settings.leader
        when "chord_wait_ms"   then settings.chord_wait_ms
        when "label.screens"   then settings.label_screens
        when "label.corner"    then settings.label_corner
        when "label.linger_ms" then settings.label_linger_ms
        when "cheat_sheet"     then settings.cheat_sheet
        else                        settings.dropdown_screens
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
        typed = typed_value(key, args.positional(2, "a value"))

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

      # A value no config could hold is a usage error, refused before the config
      # is read; one that clashes with the rest (a leader a binding starts with)
      # still fails validation.
      private def typed_value(key : String, raw : String) : JSON::Any
        case key
        when "leader"
          token = Keys.token(raw)
          raise UsageError.new("leader: #{raw.inspect} needs at least one modifier") if token.modifiers.empty?
          JSON::Any.new(token.to_s)
        when "chord_wait_ms"   then JSON::Any.new(whole(key, raw, Config::Validator::CHORD_WAIT_MS))
        when "label.linger_ms" then JSON::Any.new(whole(key, raw, Config::Validator::LINGER_MS))
        when "label.screens"   then JSON::Any.new(choice(key, raw, Config::Validator::LABEL_SCREENS))
        when "label.corner"    then JSON::Any.new(choice(key, raw, Config::Validator::LABEL_CORNERS))
        when "cheat_sheet"     then JSON::Any.new(choice(key, raw, Config::Validator::CHEAT_SHEETS))
        else                        JSON::Any.new(choice(key, raw, Config::Validator::DROPDOWN_SCREENS))
        end
      end

      private def whole(key : String, raw : String, range : Range(Int64, Int64)) : Int64
        value = raw.to_i64?
        return value if value && range.includes?(value)
        raise UsageError.new("#{key} must be a whole number from #{range.begin} to #{range.end}, got #{raw.inspect}")
      end

      private def choice(key : String, raw : String, allowed : Array(String)) : String
        return raw if allowed.includes?(raw)
        raise UsageError.new("#{key} must be one of #{allowed.join(", ")}, got #{raw.inspect}")
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
