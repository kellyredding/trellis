module Trellis
  module Commands
    module Version
      extend self

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv)
        args.at_most(0)
        if args.json?
          Support.print_json({"version" => VERSION})
        else
          STDOUT.puts "trellis #{VERSION}"
        end
        ExitCode::OK
      end
    end

    module Update
      extend self

      HELP = <<-TEXT
        trellis update — install the latest release

        Not available yet: updates arrive with release packaging.
        TEXT

      def run(argv : Array(String)) : Int32
        args = Args.parse(argv, values: ["--version"], switches: ["--local"])
        Support.help(args, HELP).try { |code| return code }
        raise Error.new("updates arrive with release packaging, which does not exist yet")
      end
    end
  end
end
