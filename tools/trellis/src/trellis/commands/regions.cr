module Trellis
  module Commands
    module Regions
      extend self

      EDGES = ["top", "right", "bottom", "left"]

      HELP = <<-TEXT
        trellis regions — margins and gaps shared by placements

        Actions:
          list
          show NAME
          add NAME [--margin-top F] [--margin-right F] [--margin-bottom F]
                   [--margin-left F] [--gap F | --gap-x F --gap-y F]
          set NAME [same options]  Changes only the values given
          remove NAME              Refused while a placement uses it

        Margins shrink the screen's visible frame, each a fraction of its width
        (left, right) or height (top, bottom); the 5% right gutter is
        --margin-right 0.05. The gap separates windows on edges that face
        another slot, as a fraction of the width (x) or height (y). Every
        value is from 0 to 0.5.

        Changes rewrite the config file, dropping its comments (see
        `trellis config --help`).
        TEXT

      VALUE_FLAGS = EDGES.map { |edge| "--margin-#{edge}" } + ["--gap", "--gap-x", "--gap-y"]

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, values: VALUE_FLAGS)
        Support.help(args, HELP).try { |code| return code }
        action = args.positional(0, "an action: list, show, add, set or remove")

        case action
        when "list"   then list(args)
        when "show"   then show(args)
        when "add"    then change(args, adding: true)
        when "set"    then change(args, adding: false)
        when "remove" then remove(args)
        else
          raise UsageError.new("unknown regions action #{action.inspect}")
        end
      end

      private def list(args : Args) : Int32
        args.at_most(1)
        model = Config::Store.model
        if args.json?
          Support.print_json do |json|
            json.object do
              json.field("regions") do
                json.array { model.regions.each { |region| region_json(json, model, region) } }
              end
            end
          end
        else
          rows = model.regions.map do |region|
            [region.name, margins_text(region), gap_text(region), users(model, region.name).join(", ")]
          end
          STDOUT.puts Format.table([["NAME", "MARGINS", "GAP", "PLACEMENTS"]] + rows)
        end
        ExitCode::OK
      end

      private def show(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a region name")
        model = Config::Store.model
        region = model.region?(name) || raise Error.new("no region named #{name.inspect}")
        if args.json?
          Support.print_json { |json| region_json(json, model, region) }
        else
          used = users(model, name)
          STDOUT.puts region.name
          STDOUT.puts "  margins     #{margins_text(region)}"
          STDOUT.puts "  gap         #{gap_text(region)}"
          STDOUT.puts "  placements  #{used.empty? ? "none" : used.join(", ")}"
        end
        ExitCode::OK
      end

      private def change(args : Args, adding : Bool) : Int32
        args.at_most(2)
        name = args.positional(1, "a region name")
        margins = EDGES.compact_map { |edge| args.float("--margin-#{edge}").try { |value| {edge, value} } }
        gap = args.float("--gap")
        gap_x = args.float("--gap-x")
        gap_y = args.float("--gap-y")
        if gap && (gap_x || gap_y)
          raise UsageError.new("give --gap, or --gap-x and --gap-y, not both")
        end
        if !adding && margins.empty? && !gap && !gap_x && !gap_y
          raise UsageError.new("set needs at least one margin or gap option")
        end

        outcome = Config::Mutation.apply do |mutation|
          regions = mutation.section("regions")
          if adding
            raise Error.new("a region named #{name.inspect} already exists") if regions.has_key?(name)
          else
            raise Error.new("no region named #{name.inspect}") unless regions.has_key?(name)
          end
          body = regions[name]?.try(&.as_h?) || {} of String => JSON::Any

          unless margins.empty?
            edges = body["margins"]?.try(&.as_h?) || {} of String => JSON::Any
            margins.each { |edge, value| edges[edge] = Support.number(value) }
            body["margins"] = JSON::Any.new(edges)
          end

          if gap
            body["gap"] = Support.number(gap)
          elsif gap_x || gap_y
            axes = {"x" => Support.number(0.0), "y" => Support.number(0.0)}
            if current = body["gap"]?
              if hash = current.as_h?
                axes.merge!(hash)
              elsif both = Config::Validator.number(current)
                axes = {"x" => Support.number(both), "y" => Support.number(both)}
              end
            end
            gap_x.try { |value| axes["x"] = Support.number(value) }
            gap_y.try { |value| axes["y"] = Support.number(value) }
            body["gap"] = JSON::Any.new(axes)
          end

          regions[name] = JSON::Any.new(body)
        end

        verb = adding ? "added" : "updated"
        Support.report_mutation(args, outcome, "#{verb} region #{name}") do |json|
          if region = outcome.model.region?(name)
            json.field("region") { region_json(json, outcome.model, region) }
          end
        end
      end

      private def remove(args : Args) : Int32
        args.at_most(2)
        name = args.positional(1, "a region name")
        used = users(Config::Store.model, name)
        unless used.empty?
          raise Error.new("refused: #{name} is used by #{used.join(", ")}; " \
                          "change or remove #{used.size == 1 ? "that placement" : "those placements"} first")
        end

        outcome = Config::Mutation.apply do |mutation|
          regions = mutation.section("regions")
          raise Error.new("no region named #{name.inspect}") unless regions.has_key?(name)
          regions.delete(name)
        end
        Support.report_mutation(args, outcome, "removed region #{name}")
      end

      private def users(model : Config::Model, name : String) : Array(String)
        model.placements.select { |placement| placement.region == name }.map(&.name)
      end

      private def margins_text(region : Config::Region) : String
        margins = region.margins
        parts = {"top" => margins.top, "right" => margins.right, "bottom" => margins.bottom, "left" => margins.left}
          .reject { |_, value| value == 0 }
          .map { |edge, value| "#{edge} #{Config.format_number(value)}" }
        parts.empty? ? "none" : parts.join(", ")
      end

      private def gap_text(region : Config::Region) : String
        if region.gap_x == region.gap_y
          Config.format_number(region.gap_x)
        else
          "x #{Config.format_number(region.gap_x)}, y #{Config.format_number(region.gap_y)}"
        end
      end

      private def region_json(json : JSON::Builder, model : Config::Model, region : Config::Region) : Nil
        json.object do
          json.field "name", region.name
          json.field("margins") do
            json.object do
              json.field("top") { Config::Export.number(json, region.margins.top) }
              json.field("right") { Config::Export.number(json, region.margins.right) }
              json.field("bottom") { Config::Export.number(json, region.margins.bottom) }
              json.field("left") { Config::Export.number(json, region.margins.left) }
            end
          end
          json.field("gap") do
            json.object do
              json.field("x") { Config::Export.number(json, region.gap_x) }
              json.field("y") { Config::Export.number(json, region.gap_y) }
            end
          end
          json.field "placements", users(model, region.name)
        end
      end
    end
  end
end
