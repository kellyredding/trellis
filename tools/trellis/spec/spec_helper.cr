require "spec"
require "file_utils"

# Reach the library without running the program. Integration examples run
# the built binary instead: exit codes and streams are only observable from
# outside the process.
ENV["TRELLIS_SKIP_CLI"] = "1"

require "../src/trellis"

module SpecHelper
  extend self

  BINARY   = File.expand_path("../build/trellis", __DIR__)
  FIXTURES = Path.new(File.expand_path("../../../fixtures", __DIR__))

  record Result, stdout : String, stderr : String, exit_code : Int32 do
    def json : JSON::Any
      JSON.parse(stdout)
    end
  end

  # One example's world: a private TRELLIS_ROOT whose socket nothing listens
  # on, so config writes never reach a real app.
  class Sandbox
    getter root : Path

    def initialize(@root : Path)
    end

    def config : Path
      @root / "config.json"
    end

    def write_config(body : String) : Nil
      File.write(config.to_s, body)
    end

    def read_config : String
      File.read(config.to_s)
    end

    def env : Hash(String, String?)
      {
        "TRELLIS_ROOT"        => @root.to_s,
        "TRELLIS_CONFIG"      => nil,
        "TRELLIS_RUNTIME_DIR" => nil,
        "TRELLIS_SOCKET"      => nil,
        "TRELLIS_SKIP_CLI"    => nil,
      } of String => String?
    end
  end

  def sandbox(&)
    dir = File.tempname("trellis-spec")
    Dir.mkdir_p(dir)
    real = Path.new(File.realpath(dir))
    begin
      yield Sandbox.new(real)
    ensure
      FileUtils.rm_rf(real.to_s)
    end
  end

  def run(sandbox : Sandbox, args : Array(String),
          extra_env : Hash(String, String?) = {} of String => String?,
          chdir : String? = nil) : Result
    unless File::Info.executable?(BINARY)
      raise "trellis is not built at #{BINARY}; run `make dev` first"
    end
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(BINARY, args, env: sandbox.env.merge(extra_env),
      output: stdout, error: stderr, chdir: chdir)
    Result.new(stdout.to_s, stderr.to_s, status.exit_code? || 128 + (status.exit_signal?.try(&.value) || 0))
  end

  # A stand-in for the app: answers each request with the reply line given
  # for its event (closing without a reply for any other event), and records
  # the requests. The socket is bound by a path relative to the sandbox, which
  # the CLI is run from, because temporary directories here can exceed the
  # 104-byte socket path limit.
  class FakeApp
    SOCKET = "app.sock"

    getter requests = [] of JSON::Any
    @server : UNIXServer

    def initialize(@dir : Path, @replies : Hash(String, String))
      @server = Dir.cd(@dir.to_s) { UNIXServer.new(SOCKET) }
      spawn { serve }
    end

    def request : JSON::Any
      requests.size.should eq(1)
      requests.first
    end

    def env : Hash(String, String?)
      {"TRELLIS_SOCKET" => SOCKET} of String => String?
    end

    def close : Nil
      @server.close rescue nil
      File.delete?((@dir / SOCKET).to_s)
    end

    private def serve : Nil
      while client = (@server.accept? rescue nil)
        begin
          line = client.gets
          next unless line
          request = JSON.parse(line)
          @requests << request
          if reply = @replies[request["event"].as_s]?
            client << reply << '\n'
          end
        rescue IO::Error
        ensure
          client.close rescue nil
        end
      end
    end
  end

  def with_app(sandbox : Sandbox, replies : Hash(String, String), &)
    app = FakeApp.new(sandbox.root, replies)
    begin
      yield app
    ensure
      app.close
    end
  end

  def run_live(sandbox : Sandbox, app : FakeApp, args : Array(String)) : Result
    run(sandbox, args, app.env, chdir: sandbox.root.to_s)
  end

  # JSON values with every number as a Float64, so `0` equals `0.0`.
  def normalize(value : JSON::Any) : JSON::Any
    case raw = value.raw
    when Int64 then JSON::Any.new(raw.to_f)
    when Array then JSON::Any.new(raw.map { |item| normalize(item) })
    when Hash  then JSON::Any.new(raw.transform_values { |item| normalize(item) })
    else            value
    end
  end

  def validate(json : String) : Trellis::Config::Result
    tree = Trellis::Config::Reader.parse(json)
    Trellis::Config::Validator.validate(tree, Trellis::Config::Source::File, Path.new("config.json"))
  end

  def errors(json : String) : Array(String)
    validate(json).errors
  end
end
