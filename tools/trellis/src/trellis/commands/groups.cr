module Trellis
  module Commands
    module Groups
      extend self

      HELP = <<-TEXT
        trellis groups — the named groups placements and actions belong to

        Actions:
          list
          add NAME [--after G | --first]   Adds at the end unless placed
          rename OLD NEW                   Also moves every placement and action in OLD
          remove NAME                      Refused while a placement or action uses it
          move NAME (--after G | --first)

        The list's order is the display order: the app's Bindings tab shows
        each group's bindings under its name, in this order. A name is any
        text, such as "60/40"; quote it in the shell when it has spaces.

        Changes rewrite the config file (see `trellis config --help`).
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, values: ["--after"], switches: ["--first"])
        Support.help(args, HELP).try { |code| return code }
        action = args.positional(0, "an action: list, add, rename, remove or move")
        if args.switch?("--first") && args["--after"]
          raise UsageError.new("give --after G or --first, not both")
        end
        if (args.switch?("--first") || args["--after"]) && !["add", "move"].includes?(action)
          raise UsageError.new("--after and --first go with add and move")
        end

        case action
        when "list"   then list(args)
        when "add"    then add(args)
        when "rename" then rename(args)
        when "remove" then remove(args)
        when "move"   then move(args)
        else
          raise UsageError.new("unknown groups action #{action.inspect}")
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        model = Config::Store.model
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("groups") do
                json.array do
                  model.groups.each do |group|
                    placements, actions = model.group_users(group)
                    json.object do
                      json.field "name", group
                      json.field "placements", placements
                      json.field "actions", actions
                      json.field "bindings", model.bindings.select { |binding| binding.group == group }.map(&.keys)
                    end
                  end
                end
              end
            end
          end
        else
          rows = model.groups.map do |group|
            placements, actions = model.group_users(group)
            bound = model.bindings.count { |binding| binding.group == group }
            [group, list_text(placements), list_text(actions), bound.to_s]
          end
          STDOUT.puts Format.table([["NAME", "PLACEMENTS", "ACTIONS", "BINDINGS"]] + rows)
        end
        ExitCode::OK
      end

      private def add(args : Args) : Int32
        args.at_most(2)
        name = Support.group_name(args.positional(1, "a group name"))

        outcome = Config::Mutation.apply do |mutation|
          groups = mutation.groups
          raise Error.new("a group named #{name.inspect} already exists") if index(groups, name)
          groups.insert(position(args, groups) || groups.size, JSON::Any.new(name))
        end
        report(args, outcome, "added group #{name}")
      end

      private def rename(args : Args) : Int32
        args.at_most(3)
        from = Support.group_name(args.positional(1, "the group's current name"))
        to = Support.group_name(args.positional(2, "its new name"))
        moved = {"placement" => 0, "action" => 0}

        outcome = Config::Mutation.apply do |mutation|
          groups = mutation.groups
          at = index(groups, from) || raise Error.new("no group named #{from.inspect}")
          raise Error.new("a group named #{to.inspect} already exists") if index(groups, to)
          groups[at] = JSON::Any.new(to)
          {"placement" => "placements", "action" => "actions"}.each do |kind, section|
            entries = mutation.section?(section)
            next unless entries
            entries.each_value do |entry|
              body = entry.as_h?
              next unless body && body["group"]?.try(&.as_s?) == from
              body["group"] = JSON::Any.new(to)
              moved[kind] += 1
            end
          end
        end

        parts = moved.reject { |_, count| count == 0 }.map { |kind, count| "#{count} #{kind}#{count == 1 ? "" : "s"}" }
        message = "renamed group #{from} to #{to}"
        message += " (moved #{parts.join(" and ")})" unless parts.empty?
        report(args, outcome, message)
      end

      private def remove(args : Args) : Int32
        args.at_most(2)
        name = Support.group_name(args.positional(1, "a group name"))
        placements, actions = Config::Store.model.group_users(name)
        users = placements + actions
        unless users.empty?
          raise Error.new("refused: group #{name.inspect} is used by #{users.join(", ")}; move " \
                          "#{users.size == 1 ? "it" : "them"} to another group first with " \
                          "`trellis placements set NAME --group G` or `trellis actions set NAME --group G`")
        end

        outcome = Config::Mutation.apply do |mutation|
          groups = mutation.groups
          at = index(groups, name) || raise Error.new("no group named #{name.inspect}")
          groups.delete_at(at)
        end
        report(args, outcome, "removed group #{name}")
      end

      private def move(args : Args) : Int32
        args.at_most(2)
        name = Support.group_name(args.positional(1, "a group name"))
        after = args["--after"].try { |text| Support.group_name(text, "--after") }
        unless after || args.switch?("--first")
          raise UsageError.new("move needs --after G or --first")
        end
        raise UsageError.new("a group cannot move after itself") if after == name

        outcome = Config::Mutation.apply do |mutation|
          groups = mutation.groups
          at = index(groups, name) || raise Error.new("no group named #{name.inspect}")
          item = groups.delete_at(at)
          groups.insert(position(args, groups) || 0, item)
        end
        report(args, outcome, after ? "moved group #{name} after #{after}" : "moved group #{name} first")
      end

      # Where --first or --after puts a group; nil when neither is given.
      private def position(args : Args, groups : Array(JSON::Any)) : Int32?
        return 0 if args.switch?("--first")
        after = args["--after"].try { |text| Support.group_name(text, "--after") }
        return nil unless after
        (index(groups, after) || raise Error.new("no group named #{after.inspect}")) + 1
      end

      private def index(groups : Array(JSON::Any), name : String) : Int32?
        groups.index { |item| item.as_s? == name }
      end

      private def list_text(names : Array(String)) : String
        names.empty? ? "-" : names.join(", ")
      end

      private def report(args : Args, outcome : Config::Mutation::Outcome, message : String) : Int32
        Support.report_mutation(args, outcome, message) do |json|
          json.field "groups", outcome.model.groups
        end
      end
    end
  end
end
