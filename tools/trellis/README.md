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
config from `config/starter.json`, both read at compile time.

## Commands

Every command takes `--json`. On failure the message goes to stderr, and
with `--json` the failure is also printed on stdout as
`{"ok": false, "error", "code", …}`.

**Live** (need the app): `status`, `screens`, `windows`, `place`,
`screen east|west`, `chord`, `reload`. A window target is nothing (the
focused window), `--window ID`, or `--app NAME [--title REGEX]`.

**Config** (no app needed): `config path|show|validate|export|init`,
`groups`, `placements`, `actions`, `regions`, `bindings`, `bind`, `unbind`,
`resolve`, `settings`.

Every placement belongs to a group (`placements add NAME --rect … --group G`),
and a built-in action needs one (`actions set screen-east --group G`) before a
chord can be bound to it. `groups list|add|rename|remove|move` manages the
ordered list; `bindings list` prints the bindings under their groups.

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

## Config changes

The config is a JSON file. Commands that change it load it (the built-in
starter when no file exists), apply the change, validate the whole result,
and refuse an invalid one without writing anything. A valid result is
written back as JSON: two-space indent, the sections in canonical order
(`version`, `settings`, `groups`, `regions`, `placements`, `actions`,
`bindings`), every other key
in its existing order. After editing the file by hand, run
`trellis config validate`.

Writes are symlink-safe: when the config path is a symlink, the file it
points to is replaced (temp file beside it, then a rename), and the link
stays a link.

After a write the CLI asks the app to reload. If the app isn't running, it
picks the change up at launch.

## Paths

| Path | Default | Override |
|---|---|---|
| Root | `~/.trellis` | `TRELLIS_ROOT` |
| Config | `<root>/config.json` | `TRELLIS_CONFIG` |
| Runtime dir | `<root>/runtime` | `TRELLIS_RUNTIME_DIR` |
| Socket | `<runtime>/trellis.sock` | `TRELLIS_SOCKET` |

Specs point all of these at a temporary directory and never touch
`~/.trellis`.
