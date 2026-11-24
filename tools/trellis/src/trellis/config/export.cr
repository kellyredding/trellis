module Trellis
  module Config
    # The JSON the app loads with `trellis config export --json`.
    #
    # MIRROR: TrellisApp/TrellisApp/Models/ConfigModel.swift
    # (docs/contract.md, "Config export"; pinned by fixtures/export.json)
    module Export
      extend self

      def to_json(model : Model) : String
        JSON.build(indent: "  ") { |json| write(json, model) }
      end

      def write(json : JSON::Builder, model : Model) : Nil
        json.object do
          json.field "version", model.version
          json.field "source", model.source.label
          json.field "path", model.path.to_s
          json.field("settings") { settings(json, model.settings) }
          json.field "groups", model.groups
          json.field("regions") do
            json.object do
              model.regions.each { |region| json.field(region.name) { self.region(json, region) } }
            end
          end
          json.field("placements") do
            json.object do
              model.placements.each { |placement| json.field(placement.name) { self.placement(json, placement) } }
            end
          end
          json.field("actions") do
            json.object do
              model.actions.each do |name, group|
                json.field(name) { json.object { json.field "group", group } }
              end
            end
          end
          json.field("bindings") do
            json.array { model.bindings.each { |binding| self.binding(json, binding) } }
          end
          json.field "warnings", model.warnings
        end
      end

      def settings(json : JSON::Builder, settings : Settings) : Nil
        json.object do
          json.field "leader", settings.leader
          json.field "chord_wait_ms", settings.chord_wait_ms
          json.field("label") do
            json.object do
              json.field "screens", settings.label_screens
              json.field "corner", settings.label_corner
              json.field "linger_ms", settings.label_linger_ms
            end
          end
        end
      end

      def region(json : JSON::Builder, region : Region) : Nil
        json.object do
          json.field("margins") do
            json.object do
              json.field("top") { number(json, region.margins.top) }
              json.field("right") { number(json, region.margins.right) }
              json.field("bottom") { number(json, region.margins.bottom) }
              json.field("left") { number(json, region.margins.left) }
            end
          end
          json.field("gap") do
            json.object do
              json.field("x") { number(json, region.gap_x) }
              json.field("y") { number(json, region.gap_y) }
            end
          end
        end
      end

      def placement(json : JSON::Builder, placement : Placement) : Nil
        json.object do
          json.field("rect") { rect(json, placement.rect) }
          json.field "region", placement.region
          json.field "group", placement.group
        end
      end

      def rect(json : JSON::Builder, rect : Rect) : Nil
        json.object do
          json.field("x") { number(json, rect.x) }
          json.field("y") { number(json, rect.y) }
          json.field("w") { number(json, rect.w) }
          json.field("h") { number(json, rect.h) }
        end
      end

      def binding(json : JSON::Builder, binding : Binding) : Nil
        json.object do
          json.field "keys", binding.keys
          json.field "chord", binding.chord
          json.field("target") { target(json, binding) }
          json.field "group", binding.group
          json.field "prefix", binding.prefix
        end
      end

      def target(json : JSON::Builder, binding : Binding) : Nil
        json.object do
          if placement = binding.placement
            json.field "placement", placement
          else
            json.field "action", binding.action
          end
        end
      end

      # Whole numbers print as integers (`0`, `1`, `10`), as the contract writes them.
      def number(json : JSON::Builder, value : Float64) : Nil
        json.raw(Config.format_number(value))
      end
    end
  end
end
