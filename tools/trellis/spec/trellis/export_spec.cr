require "../spec_helper"

private def comparable(json : JSON::Any) : JSON::Any
  hash = json.as_h.dup
  hash.delete("path")
  SpecHelper.normalize(JSON::Any.new(hash))
end

describe Trellis::Config::Export do
  it "exports fixtures/config.yml as fixtures/export.json" do
    model = Trellis::Config::Store.model(SpecHelper::FIXTURES / "config.yml")
    exported = JSON.parse(Trellis::Config::Export.to_json(model))
    expected = JSON.parse(File.read((SpecHelper::FIXTURES / "export.json").to_s))

    comparable(exported).should eq(comparable(expected))
  end

  it "reports the configured path, not the symlink's target" do
    SpecHelper.sandbox do |sandbox|
      real = sandbox.root / "real.yml"
      File.write(real.to_s, "version: 1\n")
      File.symlink(real.to_s, sandbox.config.to_s)

      model = Trellis::Config::Store.model(sandbox.config)
      JSON.parse(Trellis::Config::Export.to_json(model))["path"].should eq(sandbox.config.to_s)
    end
  end

  it "writes whole fractions as integers and the rest as decimals" do
    model = SpecHelper.validate("placements: { a: { rect: [0, 0.25, 1.0, 0.75] } }").model!
    json = Trellis::Config::Export.to_json(model)
    json.should contain(%("x": 0,))
    json.should contain(%("y": 0.25,))
    json.should contain(%("w": 1,))
  end
end

describe "the starter config" do
  it "validates without warnings and exports as the starter source" do
    SpecHelper.sandbox do |sandbox|
      loaded = Trellis::Config::Store.load(sandbox.config)
      loaded.source.should eq(Trellis::Config::Source::Starter)

      result = loaded.validate
      result.errors.should be_empty
      result.warnings.should be_empty

      exported = JSON.parse(Trellis::Config::Export.to_json(result.model!))
      exported["source"].should eq("starter")
      exported["bindings"].as_a.size.should eq(15)
      exported["regions"].as_h.should be_empty
      exported["placements"]["maximize"]["rect"].should eq(JSON.parse(%({"x": 0, "y": 0, "w": 1, "h": 1})))
    end
  end
end

describe "resolving a chord" do
  model = SpecHelper.validate("bindings: { h: screen-west, l: screen-east, \"l l\": screen-west, \"x y\": screen-east }").model!

  it "finds the binding and what it starts" do
    model.binding?(["l"]).not_nil!.action.should eq("screen-east")
    model.continuations(["l"]).map(&.keys).should eq(["l l"])
    model.continuations(["h"]).should be_empty
  end

  it "treats an unbound prefix as waiting with nothing to run" do
    model.binding?(["x"]).should be_nil
    model.continuations(["x"]).map(&.keys).should eq(["x y"])
  end

  it "has nothing for an unknown chord" do
    model.binding?(["q"]).should be_nil
    model.continuations(["q"]).should be_empty
  end
end
