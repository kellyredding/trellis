module Trellis
  # A command's arguments: positionals, `--flag value` (or `--flag=value`)
  # options, and switches. Each command names the flags it accepts, so a
  # mistyped flag is a usage error rather than a silently ignored word.
  class Args
    COMMON_SWITCHES = ["--json", "--help", "-h"]

    getter positionals = [] of String
    @values = {} of String => String
    @switches = Set(String).new

    def self.parse(argv : Array(String), values : Array(String) = [] of String,
                   switches : Array(String) = [] of String) : Args
      new.tap(&.read(argv, values, switches + COMMON_SWITCHES))
    end

    protected def read(argv : Array(String), values : Array(String), switches : Array(String)) : Nil
      index = 0
      only_positionals = false
      while index < argv.size
        argument = argv[index]
        index += 1

        if only_positionals || !argument.matches?(/\A--?[a-z]/)
          if argument == "--" && !only_positionals
            only_positionals = true
          else
            @positionals << argument
          end
        else
          name = argument
          inline = nil
          if equals = argument.index('=')
            name = argument[0, equals]
            inline = argument[(equals + 1)..]
          end
          if values.includes?(name)
            value = inline || argv[index]?
            raise UsageError.new("#{name} needs a value") if value.nil?
            index += 1 unless inline
            @values[name] = value
          elsif switches.includes?(name) && inline.nil?
            @switches << name
          else
            raise UsageError.new("unknown option #{argument}")
          end
        end
      end
    end

    def json? : Bool
      switch?("--json")
    end

    def help? : Bool
      switch?("--help") || switch?("-h")
    end

    def switch?(name : String) : Bool
      @switches.includes?(name)
    end

    def [](name : String) : String?
      @values[name]?
    end

    def positional(index : Int32, what : String) : String
      @positionals[index]? || raise UsageError.new("expected #{what}")
    end

    def at_most(count : Int32) : Nil
      if @positionals.size > count
        raise UsageError.new("unexpected argument #{@positionals[count].inspect}")
      end
    end

    def float(name : String) : Float64?
      raw = self[name]
      return nil unless raw
      raw.to_f? || raise UsageError.new("#{name} needs a number, got #{raw.inspect}")
    end
  end
end
