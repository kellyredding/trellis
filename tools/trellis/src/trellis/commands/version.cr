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
  end
end
