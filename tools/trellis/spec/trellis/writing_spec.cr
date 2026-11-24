require "../spec_helper"

describe Trellis::Config::Emitter do
  it "writes the starter and the fixture back exactly as they are" do
    [Trellis::STARTER_CONFIG, File.read((SpecHelper::FIXTURES / "config.json").to_s)].each do |text|
      Trellis::Config::Emitter.emit(Trellis::Config::Reader.parse(text).as_h).should eq(text)
    end
  end

  it "puts sections in canonical order and keeps every other key's order" do
    tree = Trellis::Config::Reader.parse(<<-JSON)
      {
        "bindings": {"l l": "b", ",": "a", "ctrl+h": "a"},
        "actions": {"screen-west": {"group": "60/40"}},
        "placements": {"b": {"rect": [0.5, 0, 0.5, 1], "region": "g"}, "a": {"rect": {"x": 0, "y": 0, "w": 1, "h": 1}}},
        "regions": {"g": {"margins": {"right": 0.05}, "gap": 0.005}, "empty": {}},
        "groups": ["Zed", "60/40"],
        "settings": {"cheat_sheet": "off", "label": {"screens": "main"}},
        "version": 1
      }
      JSON

    Trellis::Config::Emitter.emit(tree.as_h).should eq(<<-JSON)
      {
        "version": 1,
        "settings": {
          "cheat_sheet": "off",
          "label": {
            "screens": "main"
          }
        },
        "groups": ["Zed", "60/40"],
        "regions": {
          "g": {
            "margins": {
              "right": 0.05
            },
            "gap": 0.005
          },
          "empty": {}
        },
        "placements": {
          "b": {
            "rect": [0.5, 0, 0.5, 1],
            "region": "g"
          },
          "a": {
            "rect": {
              "x": 0,
              "y": 0,
              "w": 1,
              "h": 1
            }
          }
        },
        "actions": {
          "screen-west": {
            "group": "60/40"
          }
        },
        "bindings": {
          "l l": "b",
          ",": "a",
          "ctrl+h": "a"
        }
      }

      JSON
  end

  it "escapes strings and keeps every value's type" do
    tree = JSON.parse(%({"bindings": {"\\"q\\"": "a\\\\b", "1": "true", "n": null, "f": false, "list": [1, "x", null]}}))
    emitted = Trellis::Config::Emitter.emit(tree.as_h)
    Trellis::Config::Reader.parse(emitted).should eq(tree)
  end
end

describe Trellis::Config::Writer do
  it "replaces the file a symlink points to and leaves the link in place" do
    SpecHelper.sandbox do |sandbox|
      Dir.mkdir_p((sandbox.root / "dotfiles").to_s)
      real = sandbox.root / "dotfiles" / "trellis.json"
      File.write(real.to_s, "old\n")
      File.symlink("dotfiles/trellis.json", sandbox.config.to_s)

      written = Trellis::Config::Writer.write(sandbox.config, "new\n")

      written.should eq(real)
      File.symlink?(sandbox.config.to_s).should be_true
      File.read(real.to_s).should eq("new\n")
      Dir.children((sandbox.root / "dotfiles").to_s).should eq(["trellis.json"])
    end
  end

  it "follows a chain of links" do
    SpecHelper.sandbox do |sandbox|
      real = sandbox.root / "real.json"
      File.write(real.to_s, "old\n")
      File.symlink(real.to_s, (sandbox.root / "middle.json").to_s)
      File.symlink((sandbox.root / "middle.json").to_s, sandbox.config.to_s)

      Trellis::Config::Writer.write(sandbox.config, "new\n").should eq(real)
      File.symlink?((sandbox.root / "middle.json").to_s).should be_true
    end
  end

  it "resolves a relative link's .. from the link's real directory" do
    SpecHelper.sandbox do |sandbox|
      Dir.mkdir_p((sandbox.root / "dotfiles" / "trellis").to_s)
      Dir.mkdir_p((sandbox.root / "dotfiles" / "shared").to_s)
      real = sandbox.root / "dotfiles" / "shared" / "config.json"
      File.write(real.to_s, "old\n")
      File.symlink("dotfiles/trellis", (sandbox.root / "home").to_s)
      File.symlink("../shared/config.json", (sandbox.root / "home" / "config.json").to_s)

      Trellis::Config::Writer.write(sandbox.root / "home" / "config.json", "new\n").should eq(real)
      File.read(real.to_s).should eq("new\n")
      Dir.exists?((sandbox.root / "shared").to_s).should be_false
    end
  end

  it "reports a dangling link into a directory it cannot create as an error" do
    SpecHelper.sandbox do |sandbox|
      File.write((sandbox.root / "blocker").to_s, "")
      File.symlink("blocker/sub/config.json", sandbox.config.to_s)

      expect_raises(Trellis::Error, /could not write/) do
        Trellis::Config::Writer.write(sandbox.config, "new\n")
      end
    end
  end

  it "creates parent directories for a first file and keeps an existing file's mode" do
    SpecHelper.sandbox do |sandbox|
      path = sandbox.root / "a" / "b" / "config.json"
      Trellis::Config::Writer.write(path, "one\n")
      File.read(path.to_s).should eq("one\n")

      File.chmod(path.to_s, 0o600)
      Trellis::Config::Writer.write(path, "two\n")
      File.info(path.to_s).permissions.value.should eq(0o600)
    end
  end
end
