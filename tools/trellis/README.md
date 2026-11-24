# trellis

The command-line half of Trellis. It is the only reader and writer of the
layout config, and the client agents use to list and place windows through
the Trellis app. `docs/contract.md` at the repository root is the contract
between the two.

## Building

```bash
make check   # lint + dev build + specs (the specs run the dev binary)
make dev     # build/trellis, unoptimized
make build   # build/trellis, release
make install # check, build, copy to ~/.trellis/bin/trellis, link onto ~/.local/bin
```

The version comes from the repository's `VERSION` file and the starter
config from `config/starter.yml`, both read at compile time.

## Commands

Every command takes `--json`. On failure the message goes to stderr, and
with `--json` the failure is also printed on stdout as
`{"ok": false, "error", "code", …}`.

**Live** (need the app): `status`, `screens`, `windows`, `place`,
`screen east|west`, `chord`, `reload`. A window target is nothing (the
focused window), `--window ID`, or `--app NAME [--title REGEX]`.

**Config** (no app needed): `config path|show|validate|export|init`,
`placements`, `regions`, `bindings`, `bind`, `unbind`, `resolve`,
`settings`.

**Health:** `doctor`, `version`, `update` (not available until release
packaging exists).

Run `trellis <command> --help` for each command's options.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failed, including a refused config change |
| 2 | Usage error |
| 3 | The Trellis app is not running |
| 4 | Accessibility permission not granted |
| 5 | Window or screen target not found, or ambiguous |

## Config changes drop comments

Commands that change the config load it (the built-in starter when no file
exists), apply the change, validate the whole result, and refuse an invalid
one without writing anything. A valid result is written back as YAML: key
order is kept, **comments are not**. When the file had comments, the command
says so on stderr (and in `warnings` with `--json`). To keep comments, edit
the file by hand and run `trellis config validate`.

Writes are symlink-safe: when the config path is a symlink, the file it
points to is replaced (temp file beside it, then a rename), and the link
stays a link.

After a write the CLI asks the app to reload. If the app isn't running, it
picks the change up at launch.

## Paths

| Path | Default | Override |
|---|---|---|
| Root | `~/.trellis` | `TRELLIS_ROOT` |
| Config | `<root>/config.yml` | `TRELLIS_CONFIG` |
| Runtime dir | `<root>/runtime` | `TRELLIS_RUNTIME_DIR` |
| Socket | `<runtime>/trellis.sock` | `TRELLIS_SOCKET` |

Specs point all of these at a temporary directory and never touch
`~/.trellis`.
