module Trellis
  # An anticipated failure whose message is fit to be the only thing a user
  # sees. Anything else is a defect and should surface with a backtrace.
  class Error < Exception
    getter exit_code : Int32

    def initialize(message : String, @exit_code : Int32 = ExitCode::FAILED)
      super(message)
    end

    # Lines printed after the message in text mode.
    def details : Array(String)
      [] of String
    end

    def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "ok", false
        json.field "error", message
        json.field "code", code
        extra_json(json)
      end
    end

    def code : String
      "failed"
    end

    protected def extra_json(json : JSON::Builder) : Nil
    end
  end

  class UsageError < Error
    def initialize(message : String)
      super(message, ExitCode::USAGE)
    end

    def code : String
      "usage"
    end
  end

  # The config file cannot be parsed, or a change would leave it invalid.
  class InvalidConfig < Error
    getter errors : Array(String)

    def initialize(message : String, @errors : Array(String))
      super(message)
    end

    def details : Array(String)
      errors.map { |error| "  #{error}" }
    end

    def code : String
      "invalid_config"
    end

    protected def extra_json(json : JSON::Builder) : Nil
      json.field "errors", errors
    end
  end

  module ExitCode
    OK            = 0
    FAILED        = 1
    USAGE         = 2
    NOT_RUNNING   = 3
    NOT_PERMITTED = 4
    NOT_FOUND     = 5
  end
end
