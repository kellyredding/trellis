module Trellis
  module Commands
    # Helpers shared by the command modules.
    module Support
      extend self

      def help(args : Args, text : String) : Int32?
        return nil unless args.help?
        STDOUT.puts text
        ExitCode::OK
      end

      # A child's status as a shell would report it. `exit_code` raises for a
      # child a signal ended, so that is 128 plus the signal.
      def exit_code_for(status : Process::Status) : Int32
        status.exit_code? || status.exit_signal?.try { |signal| 128 + signal.value } || ExitCode::FAILED
      end

      def print_json(&block : JSON::Builder ->) : Nil
        STDOUT.puts JSON.build(indent: "  ") { |json| block.call(json) }
      end

      def print_json(value) : Nil
        STDOUT.puts value.to_pretty_json
      end

      # A number for the config tree: whole values as integers, so a written
      # rect reads `[0, 0, 0.5, 1]` rather than `[0.0, 0.0, 0.5, 1.0]`.
      def number(value : Float64) : JSON::Any
        if value == value.trunc && value.abs < 1e15
          JSON::Any.new(value.to_i64)
        else
          JSON::Any.new(value)
        end
      end

      # `X,Y,W,H` as fractions, checked against the placement rules.
      def parse_rect(text : String) : Config::Rect
        parts = text.split(',').map(&.strip)
        values = parts.map(&.to_f?)
        if parts.size != 4 || values.any?(&.nil?)
          raise UsageError.new("--rect needs four numbers X,Y,W,H, got #{text.inspect}")
        end
        tree = JSON::Any.new(values.map { |value| JSON::Any.new(value.not_nil!) })
        rect, problems = Config::Validator.rect_errors(tree)
        unless rect
          raise UsageError.new("--rect #{text}: #{problems.join("; ")}")
        end
        rect
      end

      def rect_tree(rect : Config::Rect) : JSON::Any
        JSON::Any.new([rect.x, rect.y, rect.w, rect.h].map { |value| number(value) })
      end

      def report_mutation(args : Args, outcome : Config::Mutation::Outcome, message : String,
                          &extra : JSON::Builder ->) : Int32
        if args.json?
          print_json do |json|
            json.object do
              json.field "ok", true
              json.field "message", message
              json.field "path", outcome.path.to_s
              json.field "written", outcome.written.to_s
              extra.call(json)
              json.field "reload", outcome.reload
            end
          end
        else
          STDOUT.puts message
          STDOUT.puts "  wrote #{outcome.written}" if outcome.written != outcome.path.expand
          STDOUT.puts "  #{outcome.reload.summary}"
        end
        ExitCode::OK
      end

      def report_mutation(args : Args, outcome : Config::Mutation::Outcome, message : String) : Int32
        report_mutation(args, outcome, message) { }
      end

      def bound_to(model : Config::Model, placement : String) : Array(String)
        model.bindings.select { |binding| binding.placement == placement }.map(&.keys)
      end

      def action_bound_to(model : Config::Model, action : String) : Array(String)
        model.bindings.select { |binding| binding.action == action }.map(&.keys)
      end

      # A group name as typed, trimmed; an empty one is a usage error.
      def group_name(text : String, flag : String = "a group name") : String
        name = text.strip
        raise UsageError.new("#{flag} cannot be empty") if name.empty?
        name
      end

      def group_flag(args : Args) : String?
        args["--group"].try { |text| group_name(text, "--group") }
      end
    end
  end
end
