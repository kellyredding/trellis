module Trellis
  module Commands
    module Placements
      extend self

      HELP = <<-TEXT
        trellis placements — named rects that windows are placed at

        Actions:
          list
          show NAME
          add NAME --rect X,Y,W,H [--region R] --group G
          set NAME [--rect X,Y,W,H] [--region R | --no-region] [--group G]
          rename OLD NEW           Also rewrites the bindings that target OLD
          remove NAME              Refused while a binding targets it

        A rect is x, y, width and height as fractions of the screen's visible
        frame (below the menu bar, beside the Dock), or of a region's area.
        Names use lowercase letters, digits and hyphens. Every placement
        belongs to a group from `trellis groups list`, which is where its
        bindings show in the app's Bindings tab.

        Changes rewrite the config file (see `trellis config --help`).
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, values: ["--rect", "--region", "--group"], switches: ["--no-region"])
        Support.help(args, HELP).try { |code| return code }
        action = args.positional(0, "an action: list, show, add, set, rename or remove")

        case action
        when "list"   then list(args)
        when "show"   then show(args)
        when "add"    then add(args)
        when "set"    then set(args)
        when "rename" then rename(args)
        when "remove" then remove(args)
        else
          raise UsageError.new("unknown placements action #{action.inspect}")
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        model = Config::Store.model
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("placements") do
                json.array { model.placements.each { |placement| placement_json(json, model, placement) } }
              end
            end
          end
        else
          rows = model.placements.map do |placement|
            [placement.name, "[#{placement.rect.to_s.gsub(",", ", ")}]", placement.region || "-",
             placement.group, Support.bound_to(model, placement.name).join(", ")]
          end
          STDOUT.puts Format.table([["NAME", "RECT", "REGION", "GROUP", "BINDINGS"]] + rows)
        end
        ExitCode::OK
      end

      private def show(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a placement name")
        model = Config::Store.model
        placement = model.placement?(name) || raise Error.new("no placement named #{name.inspect}")
        if args.json?
          Support.print_json { |json| placement_json(json, model, placement) }
        else
          STDOUT.puts placement.name
          STDOUT.puts "  rect      [#{placement.rect.to_s.gsub(",", ", ")}]  (x, y, w, h)"
          STDOUT.puts "  region    #{placement.region || "none"}"
          STDOUT.puts "  group     #{placement.group}"
          bound = Support.bound_to(model, placement.name)
          STDOUT.puts "  bindings  #{bound.empty? ? "none" : bound.join(", ")}"
        end
        ExitCode::OK
      end

      private def add(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a placement name")
        rect_text = args["--rect"] || raise UsageError.new("add needs --rect X,Y,W,H")
        raise UsageError.new("--no-region goes with set") if args.switch?("--no-region")
        rect = Support.parse_rect(rect_text)
        group = Support.group_flag(args) ||
                raise UsageError.new("add needs --group NAME, one of the groups in `trellis groups list`")

        outcome = Config::Mutation.apply do |mutation|
          placements = mutation.section("placements")
          raise Error.new("a placement named #{name.inspect} already exists") if placements.has_key?(name)
          body = {"rect" => Support.rect_tree(rect)}
          args["--region"].try { |region| body["region"] = JSON::Any.new(region) }
          body["group"] = JSON::Any.new(group)
          placements[name] = JSON::Any.new(body)
        end
        report(args, outcome, "added placement #{name}", name)
      end

      private def set(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a placement name")
        region = args["--region"]
        clear_region = args.switch?("--no-region")
        rect_text = args["--rect"]
        group = Support.group_flag(args)
        raise UsageError.new("give --region or --no-region, not both") if region && clear_region
        unless rect_text || region || clear_region || group
          raise UsageError.new("set needs --rect, --region, --no-region or --group")
        end
        rect = rect_text.try { |text| Support.parse_rect(text) }

        outcome = Config::Mutation.apply do |mutation|
          placements = mutation.section("placements")
          existing = placements[name]? || raise Error.new("no placement named #{name.inspect}")
          body = existing.as_h? || {} of String => JSON::Any
          body["rect"] = Support.rect_tree(rect) if rect
          body["region"] = JSON::Any.new(region) if region
          body.delete("region") if clear_region
          body["group"] = JSON::Any.new(group) if group
          placements[name] = JSON::Any.new(body)
        end
        report(args, outcome, "updated placement #{name}", name)
      end

      private def rename(args : Args) : Int32
        args.at_most(3)
        from = args.positional(1, "the placement's current name")
        to = args.positional(2, "its new name")
        rebound = 0

        outcome = Config::Mutation.apply do |mutation|
          placements = mutation.section("placements")
          raise Error.new("no placement named #{from.inspect}") unless placements.has_key?(from)
          raise Error.new("a placement named #{to.inspect} already exists") if placements.has_key?(to)
          Config::Mutation.rename_key(placements, from, to)
          mutation.section?("bindings").try do |bindings|
            bindings.keys.each do |keys|
              next unless bindings[keys].as_s? == from
              bindings[keys] = JSON::Any.new(to)
              rebound += 1
            end
          end
        end
        message = "renamed placement #{from} to #{to}"
        message += " and rebound #{rebound} binding#{rebound == 1 ? "" : "s"}" if rebound > 0
        report(args, outcome, message, to)
      end

      private def remove(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a placement name")
        model = Config::Store.model
        bound = Support.bound_to(model, name)
        unless bound.empty?
          raise Error.new("refused: #{name} is bound to #{bound.map(&.inspect).join(", ")}; " \
                          "unbind or rebind #{bound.size == 1 ? "it" : "them"} first")
        end

        outcome = Config::Mutation.apply do |mutation|
          placements = mutation.section("placements")
          raise Error.new("no placement named #{name.inspect}") unless placements.has_key?(name)
          placements.delete(name)
        end
        Support.report_mutation(args, outcome, "removed placement #{name}")
      end

      private def report(args : Args, outcome : Config::Mutation::Outcome, message : String, name : String) : Int32
        Support.report_mutation(args, outcome, message) do |json|
          if placement = outcome.model.placement?(name)
            json.field("placement") { placement_json(json, outcome.model, placement) }
          end
        end
      end

      private def placement_json(json : JSON::Builder, model : Config::Model, placement : Config::Placement) : Nil
        json.object do
          json.field "name", placement.name
          json.field("rect") { Config::Export.rect(json, placement.rect) }
          json.field "region", placement.region
          json.field "group", placement.group
          json.field "bindings", Support.bound_to(model, placement.name)
        end
      end
    end
  end
end
