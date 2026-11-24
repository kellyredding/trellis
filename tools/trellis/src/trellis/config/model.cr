module Trellis
  module Config
    BUILT_IN_ACTIONS = ["screen-east", "screen-west"]
    SECTIONS         = ["version", "settings", "regions", "placements", "bindings"]
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
      label_linger_ms : Int64 = 1500_i64,
      cheat_sheet : String = "off",
      dropdown_screens : String = "off"

    record Margins, top : Float64 = 0.0, right : Float64 = 0.0, bottom : Float64 = 0.0, left : Float64 = 0.0

    record Region, name : String, margins : Margins, gap_x : Float64, gap_y : Float64

    record Rect, x : Float64, y : Float64, w : Float64, h : Float64 do
      def to_s(io : IO) : Nil
        io << [x, y, w, h].map { |value| Config.format_number(value) }.join(",")
      end
    end

    record Placement, name : String, rect : Rect, region : String?

    record Binding, keys : String, chord : Array(String), placement : String?, action : String?, prefix : Bool do
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
      regions : Array(Region),
      placements : Array(Placement),
      bindings : Array(Binding),
      warnings : Array(String) do
      def placement?(name : String) : Placement?
        placements.find { |placement| placement.name == name }
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
