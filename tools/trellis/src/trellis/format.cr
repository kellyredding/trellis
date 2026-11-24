module Trellis
  # Text renderings of the app's window and screen objects. Each field is
  # read leniently: a missing one prints as `?` rather than failing.
  module Format
    extend self

    def window(window : JSON::Any) : String
      parts = [
        field(window, "id").ljust(7),
        field(window, "app"),
        field(window, "title").inspect,
        "screen #{field(window, "screen")}",
        frame(window["frame"]?),
      ]
      parts << "focused" if window["focused"]?.try(&.as_bool?)
      parts << "minimized" if window["minimized"]?.try(&.as_bool?)
      parts.join("  ")
    end

    def screen(screen : JSON::Any) : String
      parts = [
        field(screen, "index"),
        field(screen, "name"),
        frame(screen["frame"]?),
        "visible #{frame(screen["visible_frame"]?)}",
        "@#{field(screen, "scale")}x",
      ]
      parts << "main" if screen["main"]?.try(&.as_bool?)
      parts.join("  ")
    end

    def frame(value : JSON::Any?) : String
      return "?" unless value && value.as_h?
      "#{field(value, "w")}x#{field(value, "h")} at #{field(value, "x")},#{field(value, "y")}"
    end

    # The `config` object of the app's `status` reply. A loaded config with an
    # error is the last good one, kept after a failed reload; the error's lines
    # follow, each prefixed by `indent` and two spaces.
    def app_config(config : JSON::Any, indent : String = "") : String
      error = config["error"]?.try(&.as_s?)
      if config["loaded"]?.try(&.as_bool?)
        loaded = "loaded from #{field(config, "path")} (#{field(config, "source")})"
        return loaded unless error
        lines = error.rstrip.lines.map { |line| "#{indent}  #{line}" }
        "#{loaded} — keeping the last good config; reload failed:\n#{lines.join("\n")}"
      elsif config["state"]?.try(&.as_s?) == "loading"
        "loading…"
      elsif error
        "not loaded: #{error}"
      else
        "not loaded, and the app gave no reason"
      end
    end

    def field(object : JSON::Any, key : String) : String
      value = object.as_h? ? object[key]? : nil
      case raw = value.try(&.raw)
      when Nil     then "?"
      when String  then raw
      when Float64 then Config.format_number(raw)
      else              raw.to_s
      end
    end

    def table(rows : Array(Array(String))) : String
      return "" if rows.empty?
      widths = rows.first.size.times.map { |column| rows.max_of { |row| row[column]?.try(&.size) || 0 } }.to_a
      rows.map do |row|
        row.map_with_index { |cell, column| column == row.size - 1 ? cell : cell.ljust(widths[column]) }
          .join("  ").rstrip
      end.join("\n")
    end
  end
end
