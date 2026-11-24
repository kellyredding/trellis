require "../spec_helper"

private GUTTER_CONFIG = <<-JSON
  {
    "version": 1,
    "groups": ["Halves", "Full screen"],
    "regions": {
      "gutter": {
        "margins": {
          "right": 0.05
        },
        "gap": 0.005
      }
    },
    "placements": {
      "left-half": {
        "rect": [0, 0, 0.5, 1],
        "region": "gutter",
        "group": "Halves"
      },
      "maximize": {
        "rect": [0, 0, 1, 1],
        "group": "Full screen"
      }
    },
    "bindings": {
      "h": "left-half",
      "return": "maximize"
    }
  }

  JSON

describe "trellis version" do
  it "prints the version from the VERSION file" do
    SpecHelper.sandbox do |sandbox|
      expected = File.read(File.expand_path("../../../../VERSION", __DIR__)).strip
      SpecHelper.run(sandbox, ["version"]).stdout.should eq("trellis #{expected}\n")
      SpecHelper.run(sandbox, ["--version"]).stdout.should eq("trellis #{expected}\n")
      SpecHelper.run(sandbox, ["version", "--json"]).json["version"].should eq(expected)
    end
  end
end

describe "trellis update" do
  it "says updates come with release packaging and exits 1" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["update"])
      result.exit_code.should eq(1)
      result.stderr.should contain("release packaging")
    end
  end
end

describe "usage errors" do
  it "exit 2" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.run(sandbox, [] of String).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["reticulate"]).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["placements", "add", "x"]).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["placements", "list", "--bogus"]).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["resolve", "l  l"]).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["settings", "get", "colour"]).exit_code.should eq(2)
    end
  end
end

describe "trellis config" do
  it "uses the starter when there is no file" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["config", "export", "--json"])
      result.exit_code.should eq(0)
      result.json["source"].should eq("starter")
      result.json["path"].should eq(sandbox.config.to_s)
      File.exists?(sandbox.config.to_s).should be_false
    end
  end

  it "exports the fixture as the fixture JSON" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["config", "export", "--json"],
        {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.json").to_s})
      result.exit_code.should eq(0)
      exported = result.json.as_h.reject("path")
      expected = JSON.parse(File.read((SpecHelper::FIXTURES / "export.json").to_s)).as_h.reject("path")
      SpecHelper.normalize(JSON::Any.new(exported)).should eq(SpecHelper.normalize(JSON::Any.new(expected)))
    end
  end

  it "exits 1 with the errors on stderr for an invalid config" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(%({"version": 2, "bindings": {"h": "nowhere"}}\n))
      result = SpecHelper.run(sandbox, ["config", "export", "--json"])
      result.exit_code.should eq(1)
      result.stderr.should contain("version: must be 1")
      result.stderr.should contain("no placement or action named \"nowhere\"")

      validate = SpecHelper.run(sandbox, ["config", "validate", "--json"])
      validate.exit_code.should eq(1)
      validate.json["valid"].should eq(false)
      validate.json["errors"].as_a.size.should eq(2)
    end
  end

  it "validates and lists prefix warnings" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["config", "validate"],
        {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.json").to_s})
      result.exit_code.should eq(0)
      result.stdout.should contain("warning: l waits: it starts l l\n")
    end
  end

  it "collapses the prefix warnings to one line per waiting chord in validate and doctor" do
    SpecHelper.sandbox do |sandbox|
      bindings = ["h", "h t", "h b", "h k", "h g", "h j", "h h"].map { |keys| %("#{keys}": "left-half") }
      sandbox.write_config(GUTTER_CONFIG.sub(%("h": "left-half"), bindings.join(",\n")))

      validate = SpecHelper.run(sandbox, ["config", "validate"])
      validate.exit_code.should eq(0)
      validate.stdout.lines.count(&.starts_with?("warning: ")).should eq(1)
      validate.stdout.should contain("warning: h waits: it starts h b, h g, h h, h j, h k, h t\n")

      doctor = SpecHelper.run(sandbox, ["doctor"])
      doctor.stdout.lines.count(&.matches?(/\Awarn\s+config\s/)).should eq(1)
      doctor.stdout.should match(/warn\s+config\s+h waits: it starts h b, h g, h h, h j, h k, h t\n/)
    end
  end

  it "init writes a minimal config, refuses to overwrite, and writes the starter with --starter --force" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.run(sandbox, ["config", "init"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["config", "validate"]).exit_code.should eq(0)

      refused = SpecHelper.run(sandbox, ["config", "init", "--starter"])
      refused.exit_code.should eq(1)
      refused.stderr.should contain("--force")

      SpecHelper.run(sandbox, ["config", "init", "--starter", "--force"]).exit_code.should eq(0)
      sandbox.read_config.should eq(Trellis::STARTER_CONFIG)
    end
  end

  it "shows the file, or the starter when there is none" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.run(sandbox, ["config", "show"]).stdout.should eq(Trellis::STARTER_CONFIG)
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["config", "show"]).stdout.should eq(GUTTER_CONFIG)
    end
  end

  it "reports a file that is not JSON with where parsing stopped, and refuses changes to it" do
    SpecHelper.sandbox do |sandbox|
      broken = %({\n  "version": 1,\n}\n)
      sandbox.write_config(broken)

      validate = SpecHelper.run(sandbox, ["config", "validate", "--json"])
      validate.exit_code.should eq(1)
      validate.json["errors"].as_a.map(&.as_s).should eq([%(not valid JSON: unexpected token '}' at line 3, column 1)])

      bind = SpecHelper.run(sandbox, ["bind", "h", "maximize"])
      bind.exit_code.should eq(1)
      bind.stderr.should contain("not valid JSON")
      sandbox.read_config.should eq(broken)

      doctor = SpecHelper.run(sandbox, ["doctor"])
      doctor.exit_code.should eq(1)
      doctor.stdout.should contain("invalid: not valid JSON: ")
    end
  end
end

describe "config mutations" do
  it "writes the starter plus the change when there is no file" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["bind", "l l", "maximize"])
      result.exit_code.should eq(0)
      result.stdout.should contain("it will pick up the change at launch")

      export = SpecHelper.run(sandbox, ["config", "export", "--json"]).json
      export["source"].should eq("file")
      export["bindings"].as_a.size.should eq(16)
      export["warnings"].as_a.map(&.as_s).should eq(["l waits: it starts l l"])
    end
  end

  it "bind replaces a binding however it was spelled, and unbind removes it" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG.sub(%("h": "left-half"), %("Control+H": "left-half")))
      result = SpecHelper.run(sandbox, ["bind", "ctrl+h", "maximize", "--json"])
      result.exit_code.should eq(0)
      result.json["binding"]["target"]["placement"].should eq("maximize")
      sandbox.read_config.should contain(%("ctrl+h": "maximize"))
      sandbox.read_config.should_not contain("Control+H")

      SpecHelper.run(sandbox, ["unbind", "CTRL+H"]).exit_code.should eq(0)
      sandbox.read_config.should_not contain("ctrl+h")
      SpecHelper.run(sandbox, ["unbind", "ctrl+h"]).exit_code.should eq(1)
    end
  end

  it "refuses an invalid result and leaves the file untouched" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      [
        ["bind", "x", "nowhere"],
        ["bind", "escape", "maximize"],
        ["bind", "ctrl+s x", "maximize"],
        ["placements", "add", "Bad Name", "--rect", "0,0,1,1", "--group", "Halves"],
        ["placements", "add", "x", "--rect", "0,0,1,1", "--region", "missing", "--group", "Halves"],
        ["placements", "add", "x", "--rect", "0,0,1,1", "--group", "Nope"],
        ["placements", "set", "left-half", "--region", "missing"],
        ["placements", "set", "left-half", "--group", "Nope"],
        ["actions", "set", "screen-east", "--group", "Nope"],
        ["bind", "right", "screen-east"],
        ["regions", "add", "wide", "--margin-left", "0.5", "--margin-right", "0.5"],
      ].each do |args|
        result = SpecHelper.run(sandbox, args)
        result.exit_code.should eq(1), "#{args.join(" ")} exited #{result.exit_code}: #{result.stderr}"
        result.stderr.should contain("nothing was written")
        sandbox.read_config.should eq(GUTTER_CONFIG)
      end
    end
  end

  it "refuses an out-of-range rect as a usage error before writing" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      result = SpecHelper.run(sandbox, ["placements", "add", "wide", "--rect", "0.5,0,0.6,1"])
      result.exit_code.should eq(2)
      result.stderr.should contain("x + w must be at most 1")
      sandbox.read_config.should eq(GUTTER_CONFIG)
    end
  end

  it "adds, sets, renames and removes placements" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["placements", "add", "right-half", "--rect", "0.5,0,0.5,1", "--region", "gutter", "--group", "Halves"]).exit_code.should eq(0)
      sandbox.read_config.should contain(%("right-half": {\n      "rect": [0.5, 0, 0.5, 1],\n      "region": "gutter",\n      "group": "Halves"\n    }))

      SpecHelper.run(sandbox, ["placements", "set", "right-half", "--no-region"]).exit_code.should eq(0)
      shown = SpecHelper.run(sandbox, ["placements", "show", "right-half", "--json"]).json
      shown["region"].raw.should be_nil
      shown["group"].should eq("Halves")

      SpecHelper.run(sandbox, ["bind", "l", "right-half"]).exit_code.should eq(0)
      renamed = SpecHelper.run(sandbox, ["placements", "rename", "right-half", "east-half"])
      renamed.exit_code.should eq(0)
      renamed.stdout.should contain("rebound 1 binding")
      SpecHelper.run(sandbox, ["bindings", "show", "l", "--json"]).json["target"]["placement"].should eq("east-half")

      refused = SpecHelper.run(sandbox, ["placements", "remove", "east-half"])
      refused.exit_code.should eq(1)
      refused.stderr.should contain("bound to \"l\"")

      SpecHelper.run(sandbox, ["unbind", "l"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["placements", "remove", "east-half"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["placements", "show", "east-half"]).exit_code.should eq(1)
    end
  end

  it "adds, sets and removes regions" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["regions", "add", "stack", "--margin-right", "0.05", "--gap-x", "0.005", "--gap-y", "0.025"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["regions", "set", "gutter", "--gap-y", "0.02"]).exit_code.should eq(0)

      regions = SpecHelper.run(sandbox, ["config", "export", "--json"]).json["regions"]
      SpecHelper.normalize(regions["stack"]["gap"]).should eq(SpecHelper.normalize(JSON.parse(%({"x": 0.005, "y": 0.025}))))
      SpecHelper.normalize(regions["gutter"]["gap"]).should eq(SpecHelper.normalize(JSON.parse(%({"x": 0.005, "y": 0.02}))))

      refused = SpecHelper.run(sandbox, ["regions", "remove", "gutter"])
      refused.exit_code.should eq(1)
      refused.stderr.should contain("used by left-half")
      SpecHelper.run(sandbox, ["regions", "remove", "stack"]).exit_code.should eq(0)
    end
  end

  it "gets and sets settings by dotted key, preserving the rest of the file's order" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["settings", "get", "label.corner"]).stdout.should eq("bottom-right\n")
      SpecHelper.run(sandbox, ["settings", "set", "label.corner", "top-left"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["settings", "set", "leader", "Control+B"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["settings", "get", "leader", "--json"]).json["value"].should eq("ctrl+b")

      written = sandbox.read_config
      written.index!(%("version")).should be < written.index!(%("settings"))
      written.index!(%("settings")).should be < written.index!(%("regions"))
      written.index!(%("placements")).should be < written.index!(%("bindings"))
      written.should contain(%(  "settings": {\n    "label": {\n      "corner": "top-left"\n    },\n    "leader": "ctrl+b"\n  },\n))

      listed = SpecHelper.run(sandbox, ["settings", "list"]).stdout
      listed.should match(/label\.corner\s+top-left\s*\n/)
      listed.should match(/chord_wait_ms\s+400\s+\(default\)/)
    end
  end

  it "gets, sets and exports label.linger_ms, refusing a bad value as a usage error" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["settings", "get", "label.linger_ms"]).stdout.should eq("2000\n")
      SpecHelper.run(sandbox, ["settings", "list"]).stdout.should match(/label\.linger_ms\s+2000\s+\(default\)/)

      ["3001", "-1", "soon", "1.5"].each do |bad|
        result = SpecHelper.run(sandbox, ["settings", "set", "label.linger_ms", bad])
        result.exit_code.should eq(2), "#{bad} exited #{result.exit_code}: #{result.stderr}"
        result.stderr.should contain("0 to 3000")
        sandbox.read_config.should eq(GUTTER_CONFIG)
      end

      set = SpecHelper.run(sandbox, ["settings", "set", "label.linger_ms", "0", "--json"])
      set.exit_code.should eq(0)
      set.json["value"].should eq(0)
      sandbox.read_config.should contain(%("label": {\n      "linger_ms": 0\n    }))
      SpecHelper.run(sandbox, ["settings", "get", "label.linger_ms", "--json"]).json["value"].should eq(0)

      SpecHelper.run(sandbox, ["settings", "set", "label.linger_ms", "2500"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["config", "export", "--json"]).json["settings"]["label"]["linger_ms"].should eq(2500)
    end
  end

  it "refuses every bad settings argument as a usage error before writing" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      {
        ["nope", "1"]                => "unknown setting",
        ["chord_wait_ms", "BAD"]     => "50 to 2000",
        ["chord_wait_ms", "1.5"]     => "50 to 2000",
        ["chord_wait_ms", "49"]      => "50 to 2000",
        ["chord_wait_ms", "9000"]    => "50 to 2000",
        ["label.linger_ms", "BAD"]   => "0 to 3000",
        ["label.linger_ms", "3001"]  => "0 to 3000",
        ["label.corner", "middle"]   => "top-left, top-right",
        ["label.screens", "some"]    => "all, main, target",
        ["cheat_sheet", "on"]        => "off, label, dropdown",
        ["dropdown.screens", "Main"] => "off, all, main",
        ["leader", "s"]              => "needs at least one modifier",
        ["leader", "ctrl+nope"]      => "is not a key name",
      }.each do |argv, message|
        result = SpecHelper.run(sandbox, ["settings", "set"] + argv)
        result.exit_code.should eq(2), "#{argv.join(" ")} exited #{result.exit_code}: #{result.stderr}"
        result.stderr.should contain(message)
        sandbox.read_config.should eq(GUTTER_CONFIG)
      end
    end
  end

  it "resolves chords: bound, waiting, and unbound" do
    SpecHelper.sandbox do |sandbox|
      env = {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.json").to_s}
      waits = SpecHelper.run(sandbox, ["resolve", "l", "--json"], env).json
      waits["target"]["placement"].should eq("right-half")
      waits["prefix"].should eq(true)
      waits["wait_ms"].should eq(350)
      waits["continuations"].should eq(JSON.parse(%(["l l"])))

      at_once = SpecHelper.run(sandbox, ["resolve", "CMD+Ctrl+H", "--json"], env).json
      at_once["keys"].should eq("ctrl+cmd+h")
      at_once["prefix"].should eq(false)

      SpecHelper.run(sandbox, ["resolve", "q", "--json"], env).json["target"].raw.should be_nil
      SpecHelper.run(sandbox, ["resolve", "escape"], env).exit_code.should eq(2)
    end
  end
end

describe "groups" do
  it "add needs --group for a placement, as a usage error naming it" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      result = SpecHelper.run(sandbox, ["placements", "add", "wide", "--rect", "0,0,1,1"])
      result.exit_code.should eq(2)
      result.stderr.should contain("add needs --group NAME")
      sandbox.read_config.should eq(GUTTER_CONFIG)
    end
  end

  it "reports a placement without a group, with the command that fixes it" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG.sub(%(,\n      "group": "Full screen"), ""))
      result = SpecHelper.run(sandbox, ["config", "validate"])
      result.exit_code.should eq(1)
      result.stderr.should contain("placements.maximize: no group; set one with `trellis placements set maximize --group NAME`")
    end
  end

  it "sets a placement's group and shows it in list and show" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["placements", "set", "maximize", "--group", " Halves "]).exit_code.should eq(0)
      sandbox.read_config.should contain(%("rect": [0, 0, 1, 1],\n      "group": "Halves"))
      SpecHelper.run(sandbox, ["placements", "show", "maximize"]).stdout.should contain("  group     Halves\n")
      SpecHelper.run(sandbox, ["placements", "list"]).stdout.should match(/^maximize\s+\[0, 0, 1, 1\]\s+-\s+Halves\s+return$/m)
      SpecHelper.run(sandbox, ["placements", "list", "--json"]).json["placements"][1]["group"].should eq("Halves")

      warned = SpecHelper.run(sandbox, ["config", "validate"])
      warned.exit_code.should eq(0)
      warned.stdout.should contain(%(warning: group "Full screen" is not used by any placement or action; ))
    end
  end

  it "adds, places, moves, renames and removes groups" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      groups = -> { SpecHelper.run(sandbox, ["groups", "list", "--json"]).json["groups"].as_a.map(&.["name"].as_s) }

      SpecHelper.run(sandbox, ["groups", "add", "Displays"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["groups", "add", "60/40", "--after", "Halves"]).exit_code.should eq(0)
      added = SpecHelper.run(sandbox, ["groups", "add", "Corners", "--first", "--json"])
      added.exit_code.should eq(0)
      added.json["groups"].should eq(JSON.parse(%(["Corners", "Halves", "60/40", "Full screen", "Displays"])))
      sandbox.read_config.should contain(%(  "groups": ["Corners", "Halves", "60/40", "Full screen", "Displays"],\n))

      SpecHelper.run(sandbox, ["groups", "add", "Halves"]).stderr.should contain(%(a group named "Halves" already exists))
      SpecHelper.run(sandbox, ["groups", "add", "  "]).exit_code.should eq(2)
      SpecHelper.run(sandbox, ["groups", "add", "X", "--after", "Nope"]).stderr.should contain(%(no group named "Nope"))
      SpecHelper.run(sandbox, ["groups", "add", "X", "--after", "Halves", "--first"]).exit_code.should eq(2)

      SpecHelper.run(sandbox, ["groups", "move", "Corners", "--after", "60/40"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["groups", "move", "Displays", "--first"]).exit_code.should eq(0)
      groups.call.should eq(["Displays", "Halves", "60/40", "Corners", "Full screen"])
      SpecHelper.run(sandbox, ["groups", "move", "Corners"]).exit_code.should eq(2)

      SpecHelper.run(sandbox, ["actions", "set", "screen-east", "--group", "Halves"]).exit_code.should eq(0)
      renamed = SpecHelper.run(sandbox, ["groups", "rename", "Halves", "Sides"])
      renamed.exit_code.should eq(0)
      renamed.stdout.should contain("renamed group Halves to Sides (moved 1 placement and 1 action)")
      written = sandbox.read_config
      written.should contain(%("region": "gutter",\n      "group": "Sides"))
      written.should contain(%("screen-east": {\n      "group": "Sides"\n    }))
      written.should_not contain("Halves")

      refused = SpecHelper.run(sandbox, ["groups", "remove", "Sides"])
      refused.exit_code.should eq(1)
      refused.stderr.should contain(%(refused: group "Sides" is used by left-half, screen-east; move them to another group first))
      SpecHelper.run(sandbox, ["groups", "remove", "Corners"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["groups", "remove", "Corners"]).stderr.should contain(%(no group named "Corners"))

      listed = SpecHelper.run(sandbox, ["groups", "list"]).stdout
      listed.should match(/^Sides\s+left-half\s+screen-east\s+1$/m)
      listed.should match(/^Displays\s+-\s+-\s+0$/m)
    end
  end

  it "creates groups in canonical position in a config that has none" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(%({"bindings": {}, "version": 1}\n))
      SpecHelper.run(sandbox, ["groups", "add", "Full screen"]).exit_code.should eq(0)
      sandbox.read_config.should eq(%({\n  "version": 1,\n  "groups": ["Full screen"],\n  "bindings": {}\n}\n))
    end
  end
end

describe "actions" do
  it "lists every built-in action with its group and bindings, and sets a group" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      listed = SpecHelper.run(sandbox, ["actions", "list"]).stdout
      listed.should match(/^screen-east\s+none\s+not bound$/m)
      listed.should match(/^screen-west\s+none\s+not bound$/m)

      refused = SpecHelper.run(sandbox, ["bind", "right", "screen-east"])
      refused.exit_code.should eq(1)
      refused.stderr.should contain("refused: screen-east has no group; run `trellis actions set screen-east --group NAME` first")
      sandbox.read_config.should eq(GUTTER_CONFIG)

      SpecHelper.run(sandbox, ["groups", "add", "Displays"]).exit_code.should eq(0)
      set = SpecHelper.run(sandbox, ["actions", "set", "screen-east", "--group", "Displays", "--json"])
      set.exit_code.should eq(0)
      set.json["action"]["group"].should eq("Displays")
      sandbox.read_config.should contain(%(  "actions": {\n    "screen-east": {\n      "group": "Displays"\n    }\n  },\n  "bindings"))

      SpecHelper.run(sandbox, ["bind", "right", "screen-east"]).exit_code.should eq(0)
      actions = SpecHelper.run(sandbox, ["actions", "list", "--json"]).json["actions"]
      actions[0].should eq(JSON.parse(%({"name": "screen-east", "group": "Displays", "bound": true, "bindings": ["right"]})))
      actions[1].should eq(JSON.parse(%({"name": "screen-west", "group": null, "bound": false, "bindings": []})))

      export = SpecHelper.run(sandbox, ["config", "export", "--json"]).json
      export["actions"].should eq(JSON.parse(%({"screen-east": {"group": "Displays"}})))
    end
  end

  it "refuses an unknown action and a set without --group" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      unknown = SpecHelper.run(sandbox, ["actions", "set", "screen-north", "--group", "Halves"])
      unknown.exit_code.should eq(1)
      unknown.stderr.should contain(%(no built-in action named "screen-north"))
      SpecHelper.run(sandbox, ["actions", "set", "screen-east"]).exit_code.should eq(2)
      sandbox.read_config.should eq(GUTTER_CONFIG)
    end
  end
end

describe "trellis bindings list" do
  it "prints bindings under group headings in groups order" do
    SpecHelper.sandbox do |sandbox|
      result = SpecHelper.run(sandbox, ["bindings", "list"])
      result.exit_code.should eq(0)
      lines = result.stdout.lines
      headings = lines.reject(&.starts_with?(" "))
      headings.should eq(["Halves", "Corners", "60/40", "Full screen", "Displays"])
      lines[lines.index!("Displays") + 1].should match(/^  left\s+screen-west\s+action$/)
      lines[lines.index!("Full screen") + 1].should match(/^  return\s+maximize\s+placement$/)

      json = SpecHelper.run(sandbox, ["bindings", "list", "--json"]).json
      json["groups"].as_a.size.should eq(5)
      json["bindings"].as_a.find! { |binding| binding["keys"] == "ctrl+h" }["group"].should eq("60/40")
    end
  end

  it "skips groups with no bindings" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["bindings", "list"]).stdout.lines.reject(&.starts_with?(" ")).should eq(["Halves", "Full screen"])
      SpecHelper.run(sandbox, ["unbind", "return"]).exit_code.should eq(0)
      SpecHelper.run(sandbox, ["bindings", "list"]).stdout.lines.reject(&.starts_with?(" ")).should eq(["Halves"])
    end
  end
end

describe "symlink safety" do
  it "rewrites the file a symlinked config points to and keeps the link" do
    SpecHelper.sandbox do |sandbox|
      dotfiles = sandbox.root / "dotfiles"
      Dir.mkdir_p(dotfiles.to_s)
      real = dotfiles / "trellis.json"
      File.write(real.to_s, GUTTER_CONFIG)
      File.symlink(real.to_s, sandbox.config.to_s)

      result = SpecHelper.run(sandbox, ["bind", "l", "maximize"])
      result.exit_code.should eq(0)
      result.stdout.should contain("wrote #{real}")

      File.symlink?(sandbox.config.to_s).should be_true
      File.readlink(sandbox.config.to_s).should eq(real.to_s)
      File.read(real.to_s).should contain(%("l": "maximize"))
      Dir.children(dotfiles.to_s).should eq(["trellis.json"])

      path = SpecHelper.run(sandbox, ["config", "path", "--json"]).json
      path["path"].should eq(sandbox.config.to_s)
      path["resolved"].should eq(real.to_s)
    end
  end

  it "leaves a symlinked config untouched when a change is refused" do
    SpecHelper.sandbox do |sandbox|
      real = sandbox.root / "elsewhere.json"
      File.write(real.to_s, GUTTER_CONFIG)
      File.symlink(real.to_s, sandbox.config.to_s)

      SpecHelper.run(sandbox, ["bind", "l", "nowhere"]).exit_code.should eq(1)
      File.symlink?(sandbox.config.to_s).should be_true
      File.read(real.to_s).should eq(GUTTER_CONFIG)
    end
  end
end
