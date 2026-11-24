module Trellis
  # One request line to the app over its Unix socket and one reply line back.
  # No connection, or no reply within the timeout, means the app is not
  # running.
  #
  # MIRROR: TrellisApp/TrellisApp/Models/Envelope.swift (docs/contract.md, "Socket")
  module SocketClient
    extend self

    ENVELOPE_VERSION = 1
    READ_TIMEOUT     = 5.seconds
    WRITE_TIMEOUT    = 1.second

    class NotRunning < Error
      def initialize(reason : String)
        super("the Trellis app is not running (#{reason})", ExitCode::NOT_RUNNING)
      end

      def code : String
        "not_running"
      end
    end

    # A reply with `"ok": false`, mapped to the contract's exit codes.
    class Refused < Error
      getter reply_code : String
      getter candidates : Array(JSON::Any)

      def initialize(message : String, @reply_code : String, @candidates : Array(JSON::Any))
        super(message, Refused.exit_code_for(@reply_code))
      end

      def self.exit_code_for(code : String) : Int32
        case code
        when "not_permitted"          then ExitCode::NOT_PERMITTED
        when "not_found", "ambiguous" then ExitCode::NOT_FOUND
        else                               ExitCode::FAILED
        end
      end

      def code : String
        reply_code
      end

      def details : Array(String)
        return [] of String if candidates.empty?
        ["Candidates:"] + candidates.map { |window| "  " + Format.window(window) }
      end

      protected def extra_json(json : JSON::Builder) : Nil
        json.field "candidates", candidates unless candidates.empty?
      end
    end

    record ReloadOutcome, sent : Bool, loaded : Bool?, error : String? do
      def to_json(json : JSON::Builder) : Nil
        json.object do
          json.field "sent", sent
          json.field "loaded", loaded
          json.field "error", error
        end
      end

      def summary : String
        if !sent
          "Trellis isn't running; it will pick up the change at launch"
        elsif loaded
          "Trellis reloaded the config"
        else
          "Trellis could not reload the config: #{error || "no reason given"}"
        end
      end
    end

    def envelope(event : String, detail : Hash(String, JSON::Any)? = nil) : String
      JSON.build do |json|
        json.object do
          json.field "v", ENVELOPE_VERSION
          json.field "event", event
          json.field "ts", Time.utc.to_unix
          json.field "detail_data", detail if detail
        end
      end
    end

    # The reply's `data` on success; raises NotRunning or Refused otherwise.
    def request(event : String, detail : Hash(String, JSON::Any)? = nil,
                timeout : Time::Span = READ_TIMEOUT) : JSON::Any
      line = exchange(envelope(event, detail), timeout)
      reply = begin
        JSON.parse(line)
      rescue JSON::ParseException
        raise Error.new("the Trellis app sent a reply that is not JSON: #{line[0, 200]}")
      end

      if reply["ok"]?.try(&.as_bool?)
        reply["data"]? || JSON::Any.new({} of String => JSON::Any)
      else
        raise Refused.new(
          reply["error"]?.try(&.as_s?) || "the Trellis app refused the request",
          reply["code"]?.try(&.as_s?) || "internal",
          reply["candidates"]?.try(&.as_a?) || [] of JSON::Any,
        )
      end
    end

    # Sent after every config write. Its failure never fails the write.
    def reload_quietly : ReloadOutcome
      data = request("config.reload")
      ReloadOutcome.new(true, data["loaded"]?.try(&.as_bool?) || false, data["error"]?.try(&.as_s?))
    rescue NotRunning
      ReloadOutcome.new(false, nil, nil)
    rescue error : Error
      ReloadOutcome.new(true, false, error.message)
    end

    private def exchange(line : String, timeout : Time::Span) : String
      path = Paths.socket.to_s
      socket = begin
        UNIXSocket.new(path)
      rescue error : Socket::Error | IO::Error | File::Error | ArgumentError
        raise NotRunning.new("no connection at #{path}")
      end

      begin
        socket.sync = true
        socket.write_timeout = WRITE_TIMEOUT
        socket.read_timeout = timeout
        socket << line << '\n'
        reply = socket.gets(chomp: true)
        if reply.nil? || reply.empty?
          raise NotRunning.new("no reply at #{path}")
        end
        reply
      rescue IO::TimeoutError
        raise NotRunning.new("no reply within #{timeout.total_seconds.to_i}s at #{path}")
      rescue error : IO::Error | Socket::Error
        raise NotRunning.new("the connection failed: #{error.message}")
      ensure
        socket.close rescue nil
      end
    end
  end
end
