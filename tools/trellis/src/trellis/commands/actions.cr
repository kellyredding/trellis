module Trellis
  module Commands
    module Actions
      extend self

      HELP = <<-TEXT
        trellis actions — the built-in actions a chord can run

        Actions:
          list                     Every built-in action, its group and its bindings
          set NAME --group G       Put the action in a group

        The built-in actions are screen-east and screen-west, which move the
        window to the next display. An action needs a group before a chord can
        be bound to it.

        set rewrites the config file (see `trellis config --help`).
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, values: ["--group"])
        Support.help(args, HELP).try { |code| return code }
        case action = args.positional(0, "an action: list or set")
        when "list" then list(args)
        when "set"  then set(args)
        else
          raise UsageError.new("unknown actions action #{action.inspect}")
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        raise UsageError.new("--group goes with set") if args["--group"]
        model = Config::Store.model
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("actions") do
                json.array do
                  Config::BUILT_IN_ACTIONS.each do |name|
                    bound = Support.action_bound_to(model, name)
                    json.object do
                      json.field "name", name
                      json.field "group", model.actions[name]?
                      json.field "bound", !bound.empty?
                      json.field "bindings", bound
                    end
                  end
                end
              end
            end
          end
        else
          rows = Config::BUILT_IN_ACTIONS.map do |name|
            bound = Support.action_bound_to(model, name)
            [name, model.actions[name]? || "none", bound.empty? ? "not bound" : bound.join(", ")]
          end
          STDOUT.puts Format.table([["NAME", "GROUP", "BINDINGS"]] + rows)
        end
        ExitCode::OK
      end

      private def set(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a built-in action")
        unless Config::BUILT_IN_ACTIONS.includes?(name)
          raise Error.new("no built-in action named #{name.inspect}; " \
                          "the built-in actions are #{Config::BUILT_IN_ACTIONS.join(", ")}")
        end
        group = Support.group_flag(args) || raise UsageError.new("set needs --group NAME")

        outcome = Config::Mutation.apply do |mutation|
          actions = mutation.section("actions")
          body = actions[name]?.try(&.as_h?) || {} of String => JSON::Any
          body["group"] = JSON::Any.new(group)
          actions[name] = JSON::Any.new(body)
        end
        Support.report_mutation(args, outcome, "#{name} is in group #{group}") do |json|
          json.field("action") do
            json.object do
              json.field "name", name
              json.field "group", outcome.model.actions[name]?
              json.field "bindings", Support.action_bound_to(outcome.model, name)
            end
          end
        end
      end
    end
  end
end
