module Trellis
  # Key tokens (`ctrl+cmd+h`) and chords (`l l`): parsing and the canonical
  # form. Input is case-insensitive; the canonical form is lowercase with
  # modifiers in the order ctrl, alt, shift, cmd.
  #
  # MIRROR: TrellisApp/TrellisApp/Models/KeyToken.swift (docs/contract.md, "Key names")
  module Keys
    extend self

    MODIFIERS = {
      "ctrl"    => "ctrl",
      "control" => "ctrl",
      "alt"     => "alt",
      "opt"     => "alt",
      "option"  => "alt",
      "shift"   => "shift",
      "cmd"     => "cmd",
      "command" => "cmd",
    }

    MODIFIER_ORDER = ["ctrl", "alt", "shift", "cmd"]

    PUNCTUATION = ["`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"]

    NAMED = %w(return space tab escape delete left right up down home end pageup pagedown) +
            (1..12).map { |n| "f#{n}" }

    KEY_NAMES = (('a'..'z').map(&.to_s) + ('0'..'9').map(&.to_s) + PUNCTUATION + NAMED).to_set

    class Invalid < UsageError
    end

    record Token, modifiers : Array(String), key : String do
      def to_s(io : IO) : Nil
        modifiers.each { |modifier| io << modifier << '+' }
        io << key
      end
    end

    def token(text : String) : Token
      raise Invalid.new("a key may not be empty") if text.empty?
      parts = text.downcase.split('+')
      if parts.any?(&.empty?)
        raise Invalid.new("#{text.inspect} is not a key: modifiers and the key are joined by single \"+\"")
      end

      key = parts.pop
      unless KEY_NAMES.includes?(key)
        if MODIFIERS.has_key?(key)
          raise Invalid.new("#{text.inspect} has modifiers but no key")
        end
        raise Invalid.new("#{text.inspect} is not a key: #{key.inspect} is not a key name")
      end

      modifiers = parts.map do |part|
        MODIFIERS[part]? || raise Invalid.new(
          "#{text.inspect} is not a key: #{part.inspect} is not a modifier " \
          "(ctrl, alt, shift, cmd)")
      end
      if modifiers.uniq.size != modifiers.size
        raise Invalid.new("#{text.inspect} repeats a modifier")
      end

      Token.new(MODIFIER_ORDER.select { |name| modifiers.includes?(name) }, key)
    end

    def canonical_token(text : String) : String
      token(text).to_s
    end

    # Canonical tokens of a chord: one or more key tokens separated by single
    # spaces.
    def chord(text : String) : Array(String)
      raise Invalid.new("a chord may not be empty") if text.empty?
      parts = text.split(' ')
      if parts.any?(&.empty?)
        raise Invalid.new("#{text.inspect} is not a chord: keys are separated by single spaces")
      end
      parts.map { |part| canonical_token(part) }
    end

    def canonical_chord(text : String) : String
      chord(text).join(" ")
    end

    # A chord as it may be bound or typed after the leader.
    def bindable_chord(text : String, leader : String) : Array(String)
      tokens = chord(text)
      if tokens.any? { |token| token.split('+').last == "escape" }
        raise Invalid.new("#{text.inspect} uses escape, which leaves layout mode")
      end
      if tokens.first == leader
        raise Invalid.new("#{text.inspect} starts with the leader (#{leader})")
      end
      tokens
    end
  end
end
