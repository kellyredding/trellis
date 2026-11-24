require "../spec_helper"

private GUTTER_CONFIG = <<-YAML
  version: 1

  regions:
    gutter: { margins: { right: 0.05 }, gap: 0.005 }

  placements:
    left-half: { rect: [0, 0, 0.5, 1], region: gutter }
    maximize: { rect: [0, 0, 1, 1] }

  bindings:
    h: left-half
    return: maximize

  YAML

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
        {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.yml").to_s})
      result.exit_code.should eq(0)
      exported = result.json.as_h.reject("path")
      expected = JSON.parse(File.read((SpecHelper::FIXTURES / "export.json").to_s)).as_h.reject("path")
      SpecHelper.normalize(JSON::Any.new(exported)).should eq(SpecHelper.normalize(JSON::Any.new(expected)))
    end
  end

  it "exits 1 with the errors on stderr for an invalid config" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config("version: 2\nbindings: { h: nowhere }\n")
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
        {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.yml").to_s})
      result.exit_code.should eq(0)
      result.stdout.should contain(%(warning: "l" is the start of "l l", so it waits before running))
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
      sandbox.read_config.should eq(Trellis::STARTER_YAML)
    end
  end

  it "shows the file, or the starter when there is none" do
    SpecHelper.sandbox do |sandbox|
      SpecHelper.run(sandbox, ["config", "show"]).stdout.should eq(Trellis::STARTER_YAML)
      sandbox.write_config(GUTTER_CONFIG)
      SpecHelper.run(sandbox, ["config", "show"]).stdout.should eq(GUTTER_CONFIG)
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
      export["warnings"].as_a.map(&.as_s).should eq([%("l" is the start of "l l", so it waits before running)])
    end
  end

  it "bind replaces a binding however it was spelled, and unbind removes it" do
    SpecHelper.sandbox do |sandbox|
      sandbox.write_config(GUTTER_CONFIG.sub("h: left-half", "Control+H: left-half"))
      result = SpecHelper.run(sandbox, ["bind", "ctrl+h", "maximize", "--json"])
      result.exit_code.should eq(0)
      result.json["binding"]["target"]["placement"].should eq("maximize")
      sandbox.read_config.should contain("ctrl+h: maximize")
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
        ["settings", "set", "chord_wait_ms", "9000"],
        ["settings", "set", "label.corner", "middle"],
        ["placements", "add", "Bad Name", "--rect", "0,0,1,1"],
        ["placements", "add", "x", "--rect", "0,0,1,1", "--region", "missing"],
        ["placements", "set", "left-half", "--region", "missing"],
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
      SpecHelper.run(sandbox, ["placements", "add", "right-half", "--rect", "0.5,0,0.5,1", "--region", "gutter"]).exit_code.should eq(0)
      sandbox.read_config.should contain("right-half: { rect: [0.5, 0, 0.5, 1], region: gutter }")

      SpecHelper.run(sandbox, ["placements", "set", "right-half", "--no-region"]).exit_code.should eq(0)
      shown = SpecHelper.run(sandbox, ["placements", "show", "right-half", "--json"]).json
      shown["region"].raw.should be_nil

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
      written.index!("version").should be < written.index!("settings")
      written.index!("settings").should be < written.index!("regions")
      written.index!("placements").should be < written.index!("bindings")
      written.should contain("  label:\n    corner: top-left\n")

      listed = SpecHelper.run(sandbox, ["settings", "list"]).stdout
      listed.should match(/label\.corner\s+top-left\s*\n/)
      listed.should match(/chord_wait_ms\s+400\s+\(default\)/)
    end
  end

  it "resolves chords: bound, waiting, and unbound" do
    SpecHelper.sandbox do |sandbox|
      env = {"TRELLIS_CONFIG" => (SpecHelper::FIXTURES / "config.yml").to_s}
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

  describe "comment warnings" do
    it "warns when rewriting a file that has comments, and still writes" do
      SpecHelper.sandbox do |sandbox|
        sandbox.write_config("# mine\n" + GUTTER_CONFIG)
        warning = "warning: rewriting #{sandbox.config} drops its comments; edit the file " \
                  "directly to keep them, then `trellis config validate`"

        text = SpecHelper.run(sandbox, ["bind", "l", "maximize"])
        text.exit_code.should eq(0)
        text.stderr.should contain(warning)
        sandbox.read_config.should_not contain("# mine")
        sandbox.read_config.should contain("l: maximize")

        sandbox.write_config("# mine\n" + GUTTER_CONFIG)
        json = SpecHelper.run(sandbox, ["bind", "l", "maximize", "--json"])
        json.json["warnings"].should eq(JSON.parse([warning].to_json))
      end
    end

    it "says nothing when the file has none" do
      SpecHelper.sandbox do |sandbox|
        sandbox.write_config(GUTTER_CONFIG)
        text = SpecHelper.run(sandbox, ["bind", "l", "maximize"])
        text.stderr.should_not contain("comments")
        json = SpecHelper.run(sandbox, ["bind", "k", "maximize", "--json"])
        json.json["warnings"].as_a.should be_empty
      end
    end
  end
end

describe "symlink safety" do
  it "rewrites the file a symlinked config points to and keeps the link" do
    SpecHelper.sandbox do |sandbox|
      dotfiles = sandbox.root / "dotfiles"
      Dir.mkdir_p(dotfiles.to_s)
      real = dotfiles / "trellis.yml"
      File.write(real.to_s, GUTTER_CONFIG)
      File.symlink(real.to_s, sandbox.config.to_s)

      result = SpecHelper.run(sandbox, ["bind", "l", "maximize"])
      result.exit_code.should eq(0)
      result.stdout.should contain("wrote #{real}")

      File.symlink?(sandbox.config.to_s).should be_true
      File.readlink(sandbox.config.to_s).should eq(real.to_s)
      File.read(real.to_s).should contain("l: maximize")
      Dir.children(dotfiles.to_s).should eq(["trellis.yml"])

      path = SpecHelper.run(sandbox, ["config", "path", "--json"]).json
      path["path"].should eq(sandbox.config.to_s)
      path["resolved"].should eq(real.to_s)
    end
  end

  it "leaves a symlinked config untouched when a change is refused" do
    SpecHelper.sandbox do |sandbox|
      real = sandbox.root / "elsewhere.yml"
      File.write(real.to_s, GUTTER_CONFIG)
      File.symlink(real.to_s, sandbox.config.to_s)

      SpecHelper.run(sandbox, ["bind", "l", "nowhere"]).exit_code.should eq(1)
      File.symlink?(sandbox.config.to_s).should be_true
      File.read(real.to_s).should eq(GUTTER_CONFIG)
    end
  end
end
