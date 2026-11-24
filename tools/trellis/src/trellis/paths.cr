module Trellis
  # Every path the CLI uses, each overridable so specs run in a temporary
  # directory. The CLI never assumes the runtime directories exist.
  #
  # MIRROR: TrellisApp/TrellisApp/Models/Paths.swift (docs/contract.md, "Paths")
  module Paths
    extend self

    def root : Path
      env_path("TRELLIS_ROOT") || Path.home / ".trellis"
    end

    def config_file : Path
      env_path("TRELLIS_CONFIG") || root / "config.yml"
    end

    def runtime_dir : Path
      env_path("TRELLIS_RUNTIME_DIR") || root / "runtime"
    end

    def socket : Path
      env_path("TRELLIS_SOCKET") || runtime_dir / "trellis.sock"
    end

    def socket_lock : Path
      Path.new("#{socket}.lock")
    end

    def log_dir : Path
      runtime_dir / "logs"
    end

    def binary : Path
      env_path("TRELLIS_BINARY") || root / "bin" / "trellis"
    end

    private def env_path(name : String) : Path?
      value = ENV[name]?
      value && !value.empty? ? Path.new(value) : nil
    end
  end
end
