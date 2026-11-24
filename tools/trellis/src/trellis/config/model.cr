module Trellis
  module Config
    BUILT_IN_ACTIONS = ["screen-east", "screen-west"]
    SECTIONS         = ["version", "settings", "groups", "regions", "placements", "actions", "bindings"]
    NAME_PATTERN     = /\A[a-z0-9][a-z0-9-]*\z/

    enum Source
      File
      Starter

      def label : String
        to_s.downcase
      end
    end

    record Settings,
      leader : String = "ctrl+s",
      chord_wait_ms : Int64 = 400_i64,
      label_screens : String = "all",
      label_corner : String = "bottom-right",
      label_linger_ms : Int64 = 2000_i64

    record Margins, top : Float64 = 0.0, right : Float64 = 0.0, bottom : Float64 = 0.0, left : Float64 = 0.0

    record Region, name : String, margins : Margins, gap_x : Float64, gap_y : Float64

    record Rect, x : Float64, y : Float64, w : Float64, h : Float64 do
      def to_s(io : IO) : Nil
        io << [x, y, w, h].map { |value| Config.format_number(value) }.join(",")
      end
    end

    record Placement, name : String, rect : Rect, region : String?, group : String

    record Binding, keys : String, chord : Array(String), placement : String?, action : String?, prefix : Bool,
      group : String do
      def target_name : String
        placement || action || ""
      end

      def target_kind : String
        placement ? "placement" : "action"
      end
    end

    # The normalized config: defaults filled in, regions expanded, chords
    # canonical, bindings sorted by canonical chord.
    record Model,
      version : Int64,
      source : Source,
      path : Path,
      settings : Settings,
      groups : Array(String),
      regions : Array(Region),
      placements : Array(Placement),
      actions : Hash(String, String),
      bindings : Array(Binding),
      warnings : Array(String) do
      def placement?(name : String) : Placement?
        placements.find { |placement| placement.name == name }
      end

      # The placements, then the built-in actions, that use the group.
      def group_users(group : String) : {Array(String), Array(String)}
        {placements.select { |placement| placement.group == group }.map(&.name),
         actions.select { |_, used| used == group }.keys}
      end

      # The bindings in each group with any, in `groups` order.
      def bindings_by_group : Array({String, Array(Binding)})
        groups.compact_map do |group|
          members = bindings.select { |binding| binding.group == group }
          members.empty? ? nil : {group, members}
        end
      end

      def region?(name : String) : Region?
        regions.find { |region| region.name == name }
      end

      def binding?(chord : Array(String)) : Binding?
        bindings.find { |binding| binding.chord == chord }
      end

      # The longer bindings this chord starts; while there are any, typing it
      # waits for more keys.
      def continuations(chord : Array(String)) : Array(Binding)
        bindings.select { |other| other.chord.size > chord.size && other.chord[0, chord.size] == chord }
      end
    end

    def self.format_number(value : Float64) : String
      if value == value.trunc && value.abs < 1e15
        value.to_i64.to_s
      else
        value.to_s
      end
    end
  end
end
