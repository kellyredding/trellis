require "json"
require "socket"

# Explicit and first: the glob below loads alphabetically, and every error
# class needs its superclass defined before it.
require "./trellis/error"
require "./trellis/**"

module Trellis
  VERSION        = {{ read_file("#{__DIR__}/../../../VERSION").strip }}
  STARTER_CONFIG = {{ read_file("#{__DIR__}/../../../config/starter.json") }}
end

# Specs require this file to reach the library without running the program;
# integration specs run the built binary instead.
unless ENV.has_key?("TRELLIS_SKIP_CLI")
  Trellis::CLI.run(ARGV)
end
