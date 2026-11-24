module Trellis
  module Config
    record Result, model : Model?, errors : Array(String), warnings : Array(String) do
      def valid? : Bool
        errors.empty?
      end

      def model! : Model
        model || raise InvalidConfig.new("the config is invalid", errors)
      end
    end

    # Checks a config tree against docs/contract.md ("Validation") and builds
    # the normalized model. Every problem is reported, not just the first.
    class Validator
      TOLERANCE = 1e-9

      LABEL_SCREENS = ["all", "main", "target"]
      LABEL_CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"]
      CHORD_WAIT_MS = 50_i64..2000_i64
      LINGER_MS     = 0_i64..3000_i64

      def self.validate(tree : JSON::Any, source : Source, path : Path) : Result
        new(tree, source, path).run
      end

      @errors = [] of String

      def initialize(@tree : JSON::Any, @source : Source, @path : Path)
      end

      def run : Result
        root = object(@tree, "the config") || {} of String => JSON::Any
        root.each_key do |key|
          error("unknown top-level key #{key.inspect}") unless SECTIONS.includes?(key)
        end

        version = check_version(root["version"]?)
        settings = check_settings(root["settings"]?)
        groups = check_groups(root["groups"]?)
        region_tree = object(root["regions"]?, "regions") || {} of String => JSON::Any
        regions = check_regions(region_tree)
        placement_tree = object(root["placements"]?, "placements") || {} of String => JSON::Any
        placements = check_placements(placement_tree, region_tree.keys, groups)
        actions = check_actions(root["actions"]?, groups)
        placement_groups = placements.to_h { |placement| {placement.name, placement.group} }
        bindings = check_bindings(root["bindings"]?, settings.leader, placement_tree.keys, placement_groups, actions)

        bindings = bindings.map do |shorter|
          shorter.copy_with(prefix: bindings.any? { |binding| prefix?(shorter.chord, binding.chord) })
        end

        warnings = [] of String
        groups.each do |group|
          next if placement_groups.values.includes?(group) || actions.values.includes?(group)
          warnings << "group #{group.inspect} is not used by any placement or action; " \
                      "use it with `trellis placements set NAME --group #{Validator.shell_word(group)}`, " \
                      "or remove it with `trellis groups remove #{Validator.shell_word(group)}`"
        end

        unless @errors.empty?
          return Result.new(nil, @errors, warnings)
        end

        model = Model.new(
          version: version,
          source: @source,
          path: @path,
          settings: settings,
          groups: groups,
          regions: regions,
          placements: placements,
          actions: actions,
          bindings: bindings,
          warnings: warnings,
        )
        Result.new(model, @errors, warnings)
      end

      private def prefix?(shorter : Array(String), longer : Array(String)) : Bool
        shorter.size < longer.size && longer[0, shorter.size] == shorter
      end

      private def check_version(value : JSON::Any?) : Int64
        return 1_i64 if value.nil?
        unless value.raw == 1_i64
          error("version: must be 1, got #{show(value)}")
        end
        1_i64
      end

      private def check_settings(value : JSON::Any?) : Settings
        defaults = Settings.new
        tree = object(value, "settings")
        return defaults unless tree

        allowed_keys("settings", tree, ["leader", "chord_wait_ms", "label"])

        leader = defaults.leader
        if raw = tree["leader"]?
          if text = raw.as_s?
            begin
              token = Keys.token(text)
              if token.modifiers.empty?
                error("settings.leader: #{text.inspect} needs at least one modifier")
              else
                leader = token.to_s
              end
            rescue invalid : Keys::Invalid
              error("settings.leader: #{invalid.message}")
            end
          else
            error("settings.leader: must be a key such as ctrl+s, got #{show(raw)}")
          end
        end

        wait = defaults.chord_wait_ms
        if raw = tree["chord_wait_ms"]?
          int = raw.as_i64?
          if int && CHORD_WAIT_MS.includes?(int)
            wait = int
          else
            error("settings.chord_wait_ms: must be a whole number from 50 to 2000, got #{show(raw)}")
          end
        end

        label = object(tree["label"]?, "settings.label") || {} of String => JSON::Any
        allowed_keys("settings.label", label, ["screens", "corner", "linger_ms"])

        linger = defaults.label_linger_ms
        if raw = label["linger_ms"]?
          int = raw.as_i64?
          if int && LINGER_MS.includes?(int)
            linger = int
          else
            error("settings.label.linger_ms: must be a whole number from 0 to 3000, got #{show(raw)}")
          end
        end

        Settings.new(
          leader: leader,
          chord_wait_ms: wait,
          label_screens: choice("settings.label.screens", label["screens"]?, LABEL_SCREENS, defaults.label_screens),
          label_corner: choice("settings.label.corner", label["corner"]?, LABEL_CORNERS, defaults.label_corner),
          label_linger_ms: linger,
        )
      end

      private def check_regions(tree : Hash(String, JSON::Any)) : Array(Region)
        tree.map do |name, value|
          where = "regions.#{name}"
          check_name(where, name)
          body = value.raw.nil? ? ({} of String => JSON::Any) : object(value, where) || {} of String => JSON::Any
          allowed_keys(where, body, ["margins", "gap"])

          margins = Margins.new
          if raw = body["margins"]?
            if edges = object(raw, "#{where}.margins")
              allowed_keys("#{where}.margins", edges, ["top", "right", "bottom", "left"])
              margins = Margins.new(
                top: fraction("#{where}.margins.top", edges["top"]?),
                right: fraction("#{where}.margins.right", edges["right"]?),
                bottom: fraction("#{where}.margins.bottom", edges["bottom"]?),
                left: fraction("#{where}.margins.left", edges["left"]?),
              )
              if margins.left + margins.right >= 1
                error("#{where}.margins: left and right must sum to less than 1")
              end
              if margins.top + margins.bottom >= 1
                error("#{where}.margins: top and bottom must sum to less than 1")
              end
            end
          end

          gap_x = gap_y = 0.0
          if raw = body["gap"]?
            if axes = raw.as_h?
              allowed_keys("#{where}.gap", axes, ["x", "y"])
              gap_x = fraction("#{where}.gap.x", axes["x"]?)
              gap_y = fraction("#{where}.gap.y", axes["y"]?)
            else
              gap_x = gap_y = fraction("#{where}.gap", raw)
            end
          end

          Region.new(name, margins, gap_x, gap_y)
        end
      end

      private def check_groups(value : JSON::Any?) : Array(String)
        names = [] of String
        return names if value.nil? || value.raw.nil?
        list = value.as_a?
        unless list
          error(%(groups: must be a list of group names, such as ["Halves", "Displays"], got #{show(value)}))
          return names
        end
        list.each_with_index do |item, index|
          where = "groups[#{index}]"
          name = item.as_s?
          if name.nil?
            error("#{where}: must be a group name (a string), got #{show(item)}")
          elsif name.strip.empty?
            error("#{where}: a group name cannot be empty; remove it or give it a name")
          elsif name != name.strip
            error("#{where}: #{name.inspect} has spaces at its start or end; write it as #{name.strip.inspect}")
          elsif names.includes?(name)
            error("groups: #{name.inspect} is listed more than once; remove the repeat")
          else
            names << name
          end
        end
        names
      end

      # Built-in actions named in `actions`, each with its group.
      private def check_actions(value : JSON::Any?, groups : Array(String)) : Hash(String, String)
        actions = {} of String => String
        tree = object(value, "actions")
        return actions unless tree
        tree.each do |name, entry|
          where = "actions.#{name}"
          unless BUILT_IN_ACTIONS.includes?(name)
            error("#{where}: not a built-in action; the built-in actions are #{BUILT_IN_ACTIONS.join(", ")}")
            next
          end
          body = object(entry, where)
          next if body.nil? && !entry.raw.nil?
          body ||= {} of String => JSON::Any
          allowed_keys(where, body, ["group"])
          actions[name] = group_ref(where, body["group"]?, groups, "trellis actions set #{name} --group NAME")
        end
        actions
      end

      # The group a placement or action names, reporting a missing or unknown one
      # with the command that fixes it.
      private def group_ref(where : String, value : JSON::Any?, groups : Array(String), fix : String) : String
        if value.nil? || value.raw.nil?
          error("#{where}: no group; set one with `#{fix}`")
          return ""
        end
        name = value.as_s?
        unless name
          error("#{where}.group: must be a group name, got #{show(value)}")
          return ""
        end
        unless groups.includes?(name)
          choices = groups.empty? ? "" : ", or use one of #{groups.map(&.inspect).join(", ")}"
          error("#{where}.group: no group named #{name.inspect}; add it with " \
                "`trellis groups add #{Validator.shell_word(name)}`#{choices}")
        end
        name
      end

      # A name as it would be typed in a shell: bare when that is safe, else quoted.
      def self.shell_word(name : String) : String
        name.matches?(/\A[A-Za-z0-9_\/.,:+=@%-]+\z/) ? name : name.inspect
      end

      private def check_placements(tree : Hash(String, JSON::Any), region_names : Array(String),
                                   groups : Array(String)) : Array(Placement)
        tree.compact_map do |name, value|
          where = "placements.#{name}"
          check_name(where, name)
          if BUILT_IN_ACTIONS.includes?(name)
            error("#{where}: #{name.inspect} is a built-in action and cannot name a placement")
          end
          body = object(value, where)
          next unless body
          allowed_keys(where, body, ["rect", "region", "group"])
          group = group_ref(where, body["group"]?, groups, "trellis placements set #{name} --group NAME")

          rect_value = body["rect"]?
          unless rect_value
            error("#{where}: needs a rect")
            next
          end
          rect, problems = Validator.rect_errors(rect_value)
          problems.each { |problem| error("#{where}.rect: #{problem}") }

          region = nil
          if raw = body["region"]?
            unless raw.raw.nil?
              if text = raw.as_s?
                if region_names.includes?(text)
                  region = text
                else
                  error("#{where}.region: no region named #{text.inspect}")
                end
              else
                error("#{where}.region: must be a region name, got #{show(raw)}")
              end
            end
          end

          rect ? Placement.new(name, rect, region, group) : nil
        end
      end

      # The rect, and every problem with it. Shared with `place --rect` and
      # `placements add`, which check a rect before sending or writing it.
      def self.rect_errors(value : JSON::Any) : {Rect?, Array(String)}
        problems = [] of String
        numbers = nil
        if list = value.as_a?
          if list.size == 4 && list.all? { |item| number(item) }
            numbers = list.map { |item| number(item).not_nil! }
          end
        elsif object = value.as_h?
          if object.keys.sort == ["h", "w", "x", "y"] && object.values.all? { |item| number(item) }
            numbers = ["x", "y", "w", "h"].map { |key| number(object[key]).not_nil! }
          end
        end
        unless numbers
          return {nil, ["must be [x, y, w, h] or {x, y, w, h}, four numbers"]}
        end

        rect = Rect.new(numbers[0], numbers[1], numbers[2], numbers[3])
        problems << "x must be at least 0" if rect.x < 0
        problems << "y must be at least 0" if rect.y < 0
        problems << "w must be greater than 0" unless rect.w > 0
        problems << "h must be greater than 0" unless rect.h > 0
        problems << "x + w must be at most 1" if rect.x + rect.w > 1 + TOLERANCE
        problems << "y + h must be at most 1" if rect.y + rect.h > 1 + TOLERANCE
        {problems.empty? ? rect : nil, problems}
      end

      def self.number(value : JSON::Any) : Float64?
        case raw = value.raw
        when Int64   then raw.to_f
        when Float64 then raw
        else              nil
        end
      end

      private def check_bindings(value : JSON::Any?, leader : String, placement_names : Array(String),
                                 placement_groups : Hash(String, String), actions : Hash(String, String)) : Array(Binding)
        tree = object(value, "bindings")
        return [] of Binding unless tree

        seen = {} of Array(String) => String
        bindings = [] of Binding
        tree.each do |keys, target|
          where = "bindings #{keys.inspect}"
          chord = begin
            Keys.bindable_chord(keys, leader)
          rescue invalid : Keys::Invalid
            error("#{where}: #{invalid.message}")
            nil
          end

          name = target.as_s?
          unless name
            error("#{where}: must name a placement or action, got #{show(target)}")
            next
          end
          action = BUILT_IN_ACTIONS.includes?(name)
          unless action || placement_names.includes?(name)
            error("#{where}: no placement or action named #{name.inspect}")
            next
          end
          if action && !actions.has_key?(name)
            error("#{where}: #{name} has no group; set one with `trellis actions set #{name} --group NAME`")
            next
          end
          next unless chord

          if earlier = seen[chord]?
            error("#{where}: the same chord as #{earlier.inspect}")
            next
          end
          seen[chord] = keys
          bindings << Binding.new(
            keys: chord.join(" "),
            chord: chord,
            placement: action ? nil : name,
            action: action ? name : nil,
            prefix: false,
            group: (action ? actions[name]? : placement_groups[name]?) || "",
          )
        end
        bindings.sort_by!(&.keys)
      end

      private def choice(where : String, value : JSON::Any?, options : Array(String), default : String) : String
        return default if value.nil?
        if (text = value.as_s?) && options.includes?(text)
          text
        else
          error("#{where}: must be one of #{options.join(", ")}, got #{show(value)}")
          default
        end
      end

      private def fraction(where : String, value : JSON::Any?) : Float64
        return 0.0 if value.nil?
        number = Validator.number(value)
        if number && 0 <= number <= 0.5
          number
        else
          error("#{where}: must be a number from 0 to 0.5, got #{show(value)}")
          0.0
        end
      end

      private def check_name(where : String, name : String) : Nil
        unless name.matches?(NAME_PATTERN)
          error("#{where}: names use lowercase letters, digits and hyphens, starting with a letter or digit")
        end
      end

      private def object(value : JSON::Any?, where : String) : Hash(String, JSON::Any)?
        return nil if value.nil? || value.raw.nil?
        hash = value.as_h?
        error("#{where}: must be an object, got #{show(value)}") unless hash
        hash
      end

      private def allowed_keys(where : String, hash : Hash(String, JSON::Any), allowed : Array(String)) : Nil
        hash.each_key do |key|
          error("#{where}: unknown key #{key.inspect}") unless allowed.includes?(key)
        end
      end

      private def show(value : JSON::Any) : String
        value.to_json
      end

      private def error(message : String) : Nil
        @errors << message
      end
    end
  end
end
