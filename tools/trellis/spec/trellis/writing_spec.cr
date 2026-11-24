require "../spec_helper"

describe Trellis::Config::Emitter do
  it "round-trips the fixture to the same normalized config" do
    text = File.read((SpecHelper::FIXTURES / "config.yml").to_s)
    tree = Trellis::Config::YamlTree.parse(text)
    emitted = Trellis::Config::Emitter.emit(tree.as_h)

    Trellis::Config::YamlTree.parse(emitted).should eq(tree)
    SpecHelper.validate(emitted).model!.bindings.should eq(SpecHelper.validate(text).model!.bindings)
  end

  it "keeps key order and writes the starter's style" do
    tree = Trellis::Config::YamlTree.parse(<<-YAML)
      bindings: { "l l": b, ",": a, ctrl+h: a }
      placements: { b: { rect: [0.5, 0, 0.5, 1], region: g }, a: { rect: { x: 0, y: 0, w: 1, h: 1 } } }
      regions: { g: { margins: { right: 0.05 }, gap: 0.005 }, empty: {} }
      settings: { cheat_sheet: off, label: { screens: main } }
      YAML

    Trellis::Config::Emitter.emit(tree.as_h).should eq(<<-YAML)
      bindings:
        "l l": b
        ",": a
        ctrl+h: a

      placements:
        b: { rect: [0.5, 0, 0.5, 1], region: g }
        a: { rect: { x: 0, y: 0, w: 1, h: 1 } }

      regions:
        g:
          margins: { right: 0.05 }
          gap: 0.005
        empty: {}

      settings:
        cheat_sheet: off
        label:
          screens: main

      YAML
  end

  it "quotes strings that would read back as something else" do
    tree = JSON.parse(%({"bindings": {"1": "true", "yes": "null", "a b": "x: y", "[": "0.5"}}))
    emitted = Trellis::Config::Emitter.emit(tree.as_h)
    Trellis::Config::YamlTree.parse(emitted).should eq(tree)
  end
end

describe Trellis::Config::Writer do
  it "replaces the file a symlink points to and leaves the link in place" do
    SpecHelper.sandbox do |sandbox|
      Dir.mkdir_p((sandbox.root / "dotfiles").to_s)
      real = sandbox.root / "dotfiles" / "trellis.yml"
      File.write(real.to_s, "old\n")
      File.symlink("dotfiles/trellis.yml", sandbox.config.to_s)

      written = Trellis::Config::Writer.write(sandbox.config, "new\n")

      written.should eq(real)
      File.symlink?(sandbox.config.to_s).should be_true
      File.read(real.to_s).should eq("new\n")
      Dir.children((sandbox.root / "dotfiles").to_s).should eq(["trellis.yml"])
    end
  end

  it "follows a chain of links" do
    SpecHelper.sandbox do |sandbox|
      real = sandbox.root / "real.yml"
      File.write(real.to_s, "old\n")
      File.symlink(real.to_s, (sandbox.root / "middle.yml").to_s)
      File.symlink((sandbox.root / "middle.yml").to_s, sandbox.config.to_s)

      Trellis::Config::Writer.write(sandbox.config, "new\n").should eq(real)
      File.symlink?((sandbox.root / "middle.yml").to_s).should be_true
    end
  end

  it "resolves a relative link's .. from the link's real directory" do
    SpecHelper.sandbox do |sandbox|
      Dir.mkdir_p((sandbox.root / "dotfiles" / "trellis").to_s)
      Dir.mkdir_p((sandbox.root / "dotfiles" / "shared").to_s)
      real = sandbox.root / "dotfiles" / "shared" / "config.yml"
      File.write(real.to_s, "old\n")
      File.symlink("dotfiles/trellis", (sandbox.root / "home").to_s)
      File.symlink("../shared/config.yml", (sandbox.root / "home" / "config.yml").to_s)

      Trellis::Config::Writer.write(sandbox.root / "home" / "config.yml", "new\n").should eq(real)
      File.read(real.to_s).should eq("new\n")
      Dir.exists?((sandbox.root / "shared").to_s).should be_false
    end
  end

  it "reports a dangling link into a directory it cannot create as an error" do
    SpecHelper.sandbox do |sandbox|
      File.write((sandbox.root / "blocker").to_s, "")
      File.symlink("blocker/sub/config.yml", sandbox.config.to_s)

      expect_raises(Trellis::Error, /could not write/) do
        Trellis::Config::Writer.write(sandbox.config, "new\n")
      end
    end
  end

  it "creates parent directories for a first file and keeps an existing file's mode" do
    SpecHelper.sandbox do |sandbox|
      path = sandbox.root / "a" / "b" / "config.yml"
      Trellis::Config::Writer.write(path, "one\n")
      File.read(path.to_s).should eq("one\n")

      File.chmod(path.to_s, 0o600)
      Trellis::Config::Writer.write(path, "two\n")
      File.info(path.to_s).permissions.value.should eq(0o600)
    end
  end
end

describe "comment detection" do
  it "finds comments conservatively" do
    Trellis::Config::Store.comments?("# top\nversion: 1\n").should be_true
    Trellis::Config::Store.comments?("version: 1  # trailing\n").should be_true
    Trellis::Config::Store.comments?("a: \"quoted # still counts\"\n").should be_true
    Trellis::Config::Store.comments?("version: 1\nbindings: { a#b: x }\n").should be_false
  end
end
