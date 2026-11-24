require "../spec_helper"

describe Trellis::Keys do
  describe ".canonical_token" do
    it "lowercases and orders modifiers ctrl, alt, shift, cmd" do
      Trellis::Keys.canonical_token("CMD+Ctrl+H").should eq("ctrl+cmd+h")
      Trellis::Keys.canonical_token("cmd+shift+alt+ctrl+x").should eq("ctrl+alt+shift+cmd+x")
    end

    it "accepts the modifier aliases" do
      Trellis::Keys.canonical_token("control+h").should eq("ctrl+h")
      Trellis::Keys.canonical_token("opt+h").should eq("alt+h")
      Trellis::Keys.canonical_token("option+h").should eq("alt+h")
      Trellis::Keys.canonical_token("command+h").should eq("cmd+h")
    end

    it "accepts letters, digits, punctuation and named keys" do
      ["a", "z", "0", "9", "`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/",
       "return", "space", "tab", "escape", "delete", "left", "right", "up", "down",
       "home", "end", "pageup", "pagedown", "f1", "f12"].each do |key|
        Trellis::Keys.canonical_token(key).should eq(key)
      end
      Trellis::Keys.canonical_token("ctrl+-").should eq("ctrl+-")
      Trellis::Keys.canonical_token("Return").should eq("return")
    end

    it "rejects what is not a key token" do
      ["", "ctrl+", "+h", "ctrl++h", "ctrl", "ctrl+shift", "hyper+h", "f13", "esc",
       "enter", "h+ctrl", "ctrl+ctrl+h", "ctrl+control+h", "ab"].each do |text|
        expect_raises(Trellis::Keys::Invalid) { Trellis::Keys.canonical_token(text) }
      end
    end
  end

  describe ".chord" do
    it "splits on single spaces and canonicalizes each token" do
      Trellis::Keys.chord("l l").should eq(["l", "l"])
      Trellis::Keys.chord("Cmd+Ctrl+H x").should eq(["ctrl+cmd+h", "x"])
      Trellis::Keys.canonical_chord("Control+L L").should eq("ctrl+l l")
    end

    it "rejects empty chords and stray spaces" do
      ["", " ", "l  l", " l", "l "].each do |text|
        expect_raises(Trellis::Keys::Invalid) { Trellis::Keys.chord(text) }
      end
    end
  end

  describe ".bindable_chord" do
    it "rejects escape anywhere in the chord" do
      expect_raises(Trellis::Keys::Invalid, /escape/) { Trellis::Keys.bindable_chord("l escape", "ctrl+s") }
      expect_raises(Trellis::Keys::Invalid, /escape/) { Trellis::Keys.bindable_chord("shift+escape", "ctrl+s") }
    end

    it "rejects a chord that starts with the leader, in any spelling" do
      expect_raises(Trellis::Keys::Invalid, /leader/) { Trellis::Keys.bindable_chord("Control+S h", "ctrl+s") }
      Trellis::Keys.bindable_chord("h ctrl+s", "ctrl+s").should eq(["h", "ctrl+s"])
    end
  end
end
