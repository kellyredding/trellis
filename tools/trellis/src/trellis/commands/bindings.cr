module Trellis
  module Commands
    # `bindings list|show`, `bind` and `unbind`.
    module Bindings
      extend self

      HELP = <<-TEXT
        trellis bindings list | show CHORD
        trellis bind CHORD TARGET
        trellis unbind CHORD

        A chord is one or more keys separated by single spaces, typed after the
        leader (⌃S): "h", "l l", "ctrl+h". Modifiers are ctrl, alt, shift and
        cmd (control, opt, option and command also work), joined to the key by
        "+". TARGET is a placement name or a built-in action: screen-east,
        screen-west.

        A chord that also starts a longer one waits (chord_wait_ms) before it
        runs; `trellis resolve CHORD` says whether one does.

        bind and unbind rewrite the config file (see `trellis config --help`).
        TEXT

      def run(command : String, argv : Array(String)) : Int32
        args = Args.parse(argv)
        Support.help(args, HELP).try { |code| return code }

        case command
        when "bind"   then bind(args)
        when "unbind" then unbind(args)
        else
          case action = args.positional(0, "an action: list or show")
          when "list" then list(args)
          when "show" then show(args)
          else
            raise UsageError.new("unknown bindings action #{action.inspect}")
          end
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        model = Config::Store.model
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("bindings") do
                json.array { model.bindings.each { |binding| Config::Export.binding(json, binding) } }
              end
              json.field "warnings", model.warnings
            end
          end
        else
          rows = model.bindings.map do |binding|
            [binding.keys, binding.target_name, binding.target_kind, binding.prefix ? "waits" : ""]
          end
          STDOUT.puts Format.table([["CHORD", "TARGET", "KIND", ""]] + rows)
        end
        ExitCode::OK
      end

      private def show(args : Args) : Int32
        args.at_most(2)
        text = args.positional(1, "a chord")
        model = Config::Store.model
        chord = Keys.chord(text)
        binding = model.binding?(chord) || raise Error.new("#{chord.join(" ").inspect} is not bound")
        if args.json?
          Support.print_json { |json| Config::Export.binding(json, binding) }
        else
          STDOUT.puts "#{binding.keys} -> #{binding.target_name} (#{binding.target_kind})#{binding.prefix ? ", waits" : ""}"
        end
        ExitCode::OK
      end

      private def bind(args : Args) : Int32
        args.at_most(2)
        text = args.positional(0, "a chord")
        target = args.positional(1, "a placement name or action")
        chord = Keys.chord(text)
        keys = chord.join(" ")
        replaced = nil

        outcome = Config::Mutation.apply do |mutation|
          bindings = mutation.section("bindings")
          if existing = matching_key(bindings, chord)
            replaced = bindings[existing].as_s? || bindings[existing].to_json
            Config::Mutation.rename_key(bindings, existing, keys)
          end
          bindings[keys] = JSON::Any.new(target)
        end

        message = "bound #{keys} to #{target}"
        message += " (was #{replaced})" if replaced && replaced != target
        Support.report_mutation(args, outcome, message) do |json|
          if binding = outcome.model.binding?(chord)
            json.field("binding") { Config::Export.binding(json, binding) }
          end
        end
      end

      private def unbind(args : Args) : Int32
        args.at_most(1)
        chord = Keys.chord(args.positional(0, "a chord"))
        keys = chord.join(" ")

        outcome = Config::Mutation.apply do |mutation|
          bindings = mutation.section("bindings")
          existing = matching_key(bindings, chord) || raise Error.new("#{keys.inspect} is not bound")
          bindings.delete(existing)
        end
        Support.report_mutation(args, outcome, "unbound #{keys}")
      end

      # The key in the file that spells this chord, however it is written.
      private def matching_key(bindings : Hash(String, JSON::Any), chord : Array(String)) : String?
        bindings.each_key.find do |key|
          begin
            Keys.chord(key) == chord
          rescue Keys::Invalid
            false
          end
        end
      end
    end

    module Resolve
      extend self

      HELP = <<-TEXT
        trellis resolve CHORD — what a chord runs, from the config alone

        Says which placement or action the chord is bound to, and whether it
        waits: a chord that also starts a longer one waits chord_wait_ms
        before running, so the longer one can be typed.
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv)
        Support.help(args, HELP).try { |code| return code }
        args.at_most(1)
        text = args.positional(0, "a chord")
        model = Config::Store.model
        chord = Keys.bindable_chord(text, model.settings.leader)
        keys = chord.join(" ")
        binding = model.binding?(chord)
        longer = model.continuations(chord)
        waits = !longer.empty?

        if args.json?
          Support.print_json do |json|
            json.object do
              json.field "keys", keys
              json.field "chord", chord
              json.field("target") { binding ? Config::Export.target(json, binding) : json.null }
              json.field "prefix", waits
              json.field "wait_ms", waits ? model.settings.chord_wait_ms : nil
              json.field "continuations", longer.map(&.keys)
            end
          end
        else
          continuations = longer.map { |other| %("#{other.keys}") }.join(", ")
          if binding && waits
            STDOUT.puts "#{keys} -> #{binding.target_name} (#{binding.target_kind}), after waiting " \
                        "#{model.settings.chord_wait_ms} ms: it starts #{continuations}"
          elsif binding
            STDOUT.puts "#{keys} -> #{binding.target_name} (#{binding.target_kind}), at once"
          elsif waits
            STDOUT.puts "#{keys} is not bound; it starts #{continuations}, so it waits for more keys"
          else
            STDOUT.puts "#{keys} is not bound"
          end
        end
        ExitCode::OK
      end
    end
  end
end
