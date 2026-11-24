require "../spec_helper"

private def placements(body : String) : String
  %({"placements": {#{body}}})
end

describe Trellis::Config::Validator do
  it "accepts an empty config and fills every default" do
    result = SpecHelper.validate("{}")
    result.errors.should be_empty
    model = result.model!
    model.version.should eq(1)
    model.settings.should eq(Trellis::Config::Settings.new)
    model.settings.leader.should eq("ctrl+s")
    model.settings.chord_wait_ms.should eq(400)
    model.bindings.should be_empty
  end

  it "needs the config to be an object" do
    SpecHelper.errors("[]").should eq(["the config: must be an object, got []"])
  end

  describe "version" do
    it "must be 1" do
      SpecHelper.errors(%({"version": 2})).should eq(["version: must be 1, got 2"])
      SpecHelper.errors(%({"version": "1"})).first.should contain("must be 1")
    end
  end

  describe "settings" do
    it "range-checks chord_wait_ms" do
      SpecHelper.errors(%({"settings": {"chord_wait_ms": 49}})).first.should contain("50 to 2000")
      SpecHelper.errors(%({"settings": {"chord_wait_ms": 2001}})).first.should contain("50 to 2000")
      SpecHelper.errors(%({"settings": {"chord_wait_ms": 400.5}})).first.should contain("whole number")
      SpecHelper.errors(%({"settings": {"chord_wait_ms": 50}})).should be_empty
      SpecHelper.errors(%({"settings": {"chord_wait_ms": 2000}})).should be_empty
    end

    it "checks each enumeration" do
      SpecHelper.errors(%({"settings": {"label": {"screens": "some"}}})).first.should contain("all, main, target")
      SpecHelper.errors(%({"settings": {"label": {"corner": "middle"}}})).first.should contain("bottom-right")
      SpecHelper.errors(%({"settings": {"cheat_sheet": "on"}})).first.should contain("off, label, dropdown")
      SpecHelper.errors(%({"settings": {"cheat_sheet": false}})).first.should contain("off, label, dropdown")
      SpecHelper.errors(%({"settings": {"dropdown": {"screens": "target"}}})).first.should contain("off, all, main")
      SpecHelper.errors(%({"settings": {"cheat_sheet": "off", "dropdown": {"screens": "off"}}})).should be_empty
    end

    it "needs a leader that is one key token with a modifier" do
      SpecHelper.errors(%({"settings": {"leader": "s"}})).first.should contain("at least one modifier")
      SpecHelper.errors(%({"settings": {"leader": "ctrl+s x"}})).first.should contain("settings.leader")
      SpecHelper.validate(%({"settings": {"leader": "Control+S"}})).model!.settings.leader.should eq("ctrl+s")
    end

    it "rejects unknown keys" do
      SpecHelper.errors(%({"settings": {"colour": "red"}})).first.should contain("unknown key \"colour\"")
      SpecHelper.errors(%({"arrangements": {}})).first.should contain("unknown top-level key")
    end
  end

  describe "regions" do
    it "bounds each margin and gap to 0..0.5" do
      SpecHelper.errors(%({"regions": {"a": {"margins": {"right": 0.6}}}})).first.should contain("0 to 0.5")
      SpecHelper.errors(%({"regions": {"a": {"margins": {"top": -0.1}}}})).first.should contain("0 to 0.5")
      SpecHelper.errors(%({"regions": {"a": {"gap": 0.51}}})).first.should contain("regions.a.gap")
      SpecHelper.errors(%({"regions": {"a": {"gap": {"x": 0.1, "y": 0.7}}}})).first.should contain("regions.a.gap.y")
    end

    it "needs each axis's margins to sum to less than 1" do
      SpecHelper.errors(%({"regions": {"a": {"margins": {"left": 0.5, "right": 0.5}}}}))
        .should eq(["regions.a.margins: left and right must sum to less than 1"])
      SpecHelper.errors(%({"regions": {"a": {"margins": {"top": 0.5, "bottom": 0.5}}}}))
        .should eq(["regions.a.margins: top and bottom must sum to less than 1"])
      SpecHelper.errors(%({"regions": {"a": {"margins": {"left": 0.5, "right": 0.49}}}})).should be_empty
    end

    it "expands both gap forms and missing margins" do
      model = SpecHelper.validate(%({"regions": {"a": {"gap": 0.01}, "b": {"gap": {"x": 0.02, "y": 0.03}}, "c": null}})).model!
      model.regions.map { |region| {region.name, region.gap_x, region.gap_y} }
        .should eq([{"a", 0.01, 0.01}, {"b", 0.02, 0.03}, {"c", 0.0, 0.0}])
      model.regions.first.margins.should eq(Trellis::Config::Margins.new)
    end
  end

  describe "placements" do
    it "accepts both rect forms" do
      model = SpecHelper.validate(placements(%("a": {"rect": [0, 0, 0.5, 1]}, "b": {"rect": {"x": 0.5, "y": 0, "w": 0.5, "h": 1}}))).model!
      model.placements.map(&.rect).should eq([
        Trellis::Config::Rect.new(0.0, 0.0, 0.5, 1.0),
        Trellis::Config::Rect.new(0.5, 0.0, 0.5, 1.0),
      ])
    end

    it "checks the rect's bounds" do
      SpecHelper.errors(placements(%("a": {"rect": [-0.1, 0, 0.5, 1]}))).should eq(["placements.a.rect: x must be at least 0"])
      SpecHelper.errors(placements(%("a": {"rect": [0, -0.1, 0.5, 1]}))).should eq(["placements.a.rect: y must be at least 0"])
      SpecHelper.errors(placements(%("a": {"rect": [0, 0, 0, 1]}))).should eq(["placements.a.rect: w must be greater than 0"])
      SpecHelper.errors(placements(%("a": {"rect": [0, 0, 1, 0]}))).should eq(["placements.a.rect: h must be greater than 0"])
      SpecHelper.errors(placements(%("a": {"rect": [0.6, 0, 0.5, 1]}))).should eq(["placements.a.rect: x + w must be at most 1"])
      SpecHelper.errors(placements(%("a": {"rect": [0, 0.6, 1, 0.5]}))).should eq(["placements.a.rect: y + h must be at most 1"])
    end

    it "allows sums within 1e-9 of 1" do
      SpecHelper.errors(placements(%("a": {"rect": [0.6, 0, 0.4000000001, 1]}))).should be_empty
      SpecHelper.errors(placements(%("a": {"rect": [0.6, 0, 0.400001, 1]}))).should_not be_empty
    end

    it "rejects malformed rects" do
      [%([0, 0, 1]), %([0, 0, 1, 1, 1]), %([0, 0, "a", 1]), %({"x": 0, "y": 0, "w": 1}), %(0.5)].each do |rect|
        SpecHelper.errors(placements(%("a": {"rect": #{rect}}))).first.should contain("four numbers")
      end
      SpecHelper.errors(placements(%("a": {"region": "x"}))).should contain("placements.a: needs a rect")
    end

    it "needs the region to exist" do
      SpecHelper.errors(placements(%("a": {"rect": [0, 0, 1, 1], "region": "gutter"})))
        .should eq(["placements.a.region: no region named \"gutter\""])
      SpecHelper.validate(placements(%("a": {"rect": [0, 0, 1, 1], "region": null}))).model!.placements.first.region.should be_nil
    end

    it "checks the name" do
      SpecHelper.errors(placements(%("Left": {"rect": [0, 0, 1, 1]}))).first.should contain("lowercase letters")
      SpecHelper.errors(placements(%("-left": {"rect": [0, 0, 1, 1]}))).first.should contain("lowercase letters")
      SpecHelper.errors(placements(%("screen-east": {"rect": [0, 0, 1, 1]}))).first.should contain("built-in action")
    end
  end

  describe "bindings" do
    it "needs each key to parse as a chord" do
      SpecHelper.errors(%({"bindings": {"hyper+h": "screen-east"}})).first.should contain("not a modifier")
    end

    it "needs each value to name a placement or a built-in action" do
      SpecHelper.errors(%({"bindings": {"h": "nowhere"}})).should eq(["bindings \"h\": no placement or action named \"nowhere\""])
      SpecHelper.errors(%({"bindings": {"h": "screen-west"}})).should be_empty
    end

    it "rejects escape and the leader" do
      SpecHelper.errors(%({"bindings": {"escape": "screen-east"}})).first.should contain("escape")
      SpecHelper.errors(%({"bindings": {"ctrl+s h": "screen-east"}})).first.should contain("leader")
      SpecHelper.errors(%({"settings": {"leader": "ctrl+b"}, "bindings": {"ctrl+s h": "screen-east"}})).should be_empty
    end

    it "rejects two spellings of one chord" do
      SpecHelper.errors(%({"bindings": {"ctrl+h": "screen-east", "control+h": "screen-west"}}))
        .should eq(["bindings \"control+h\": the same chord as \"ctrl+h\""])
    end

    it "canonicalizes and sorts by canonical chord" do
      model = SpecHelper.validate(%({"bindings": {"t": "screen-east", "CMD+Ctrl+H": "screen-west", "l l": "screen-east", "l": "screen-west"}})).model!
      model.bindings.map(&.keys).should eq(["ctrl+cmd+h", "l", "l l", "t"])
      model.bindings.find! { |binding| binding.keys == "ctrl+cmd+h" }.chord.should eq(["ctrl+cmd+h"])
    end
  end

  describe "prefix warnings" do
    it "warns once per pair, worded exactly, sorted by prefix then longer chord" do
      result = SpecHelper.validate(<<-JSON)
        {
          "bindings": {
            "l l": "screen-east",
            "a b c": "screen-east",
            "l": "screen-west",
            "a": "screen-west",
            "a b": "screen-west",
            "l l x": "screen-east"
          }
        }
        JSON
      result.errors.should be_empty
      result.warnings.should eq([
        %("a" is the start of "a b", so it waits before running),
        %("a" is the start of "a b c", so it waits before running),
        %("a b" is the start of "a b c", so it waits before running),
        %("l" is the start of "l l", so it waits before running),
        %("l" is the start of "l l x", so it waits before running),
        %("l l" is the start of "l l x", so it waits before running),
      ])
      result.model!.bindings.select(&.prefix).map(&.keys).should eq(["a", "a b", "l", "l l"])
    end

    it "does not count a chord whose first token merely shares a key" do
      SpecHelper.validate(%({"bindings": {"l": "screen-east", "ctrl+l x": "screen-west"}})).warnings.should be_empty
    end
  end

  it "reports every problem, not just the first" do
    SpecHelper.errors(%({"version": 3, "settings": {"chord_wait_ms": 1}, "bindings": {"h": "nowhere"}})).size.should eq(3)
  end
end

describe Trellis::Config::Reader do
  it "reads strict JSON and reports where it stops parsing" do
    {
      ""                                  => "line 1, column 1",
      %({"placements": [})                => "line 1, column 17",
      %({\n  "version": 1,\n}\n)          => "line 3, column 1",
      %({"bindings": {"h": "a",}})        => "line 1, column 24",
      %(// mine\n{"version": 1}\n)        => "line 1, column 1",
      %({"version": 1 /* mine */}\n)      => "line 1, column 15",
      %({"version": 1}\n{"version": 1}\n) => "line 2, column 1",
    }.each do |text, location|
      error = expect_raises(Trellis::InvalidConfig) { Trellis::Config::Reader.parse(text) }
      error.errors.size.should eq(1)
      error.errors.first.should start_with("not valid JSON: ")
      error.errors.first.should contain(location), "#{text.inspect}: #{error.errors.first}"
    end
  end

  it "rejects a repeated key at any depth, naming where" do
    error = expect_raises(Trellis::InvalidConfig) do
      Trellis::Config::Reader.parse(%({\n  "bindings": {\n    "h": "a",\n    "h": "b"\n  }\n}\n))
    end
    error.errors.should eq([%(not valid JSON: duplicate key "h" at line 4, column 5)])
  end

  it "keeps key order" do
    Trellis::Config::Reader.parse(%({"b": 1, "a": {"z": 1, "y": 2}})).to_json.should eq(%({"b":1,"a":{"z":1,"y":2}}))
  end
end
