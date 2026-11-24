# Trellis

Keyboard window layout for macOS, with a CLI built for agents.

Press ⌃S and Trellis enters layout mode: a label appears on every screen, and
the next chord places the focused window — `h` for the left half, `l l` for
the right half without a gutter, `return` to fill the screen. Chords are any
sequence of keys typed within a short wait; each key restarts the wait, so
`l` and `l l` can both be bindings.

Layouts are data, not code. A placement is a rect in fractions of the
screen's visible frame, optionally inside a named region that keeps margins
clear and leaves gaps between neighbouring windows. Bindings map chords to
placements. All of it lives in one JSON file that the `trellis` CLI reads,
validates and edits, so an agent can list your windows, try a shape on one,
and add the binding you liked.

## Parts

- **Trellis.app** (`TrellisApp/`) — a menu-bar app. It holds the macOS
  Accessibility permission, owns the ⌃S leader and layout mode, and moves
  windows.
- **`trellis`** (`tools/trellis/`) — the CLI. It is the only reader and
  writer of the config, and talks to the app over a Unix socket for anything
  that touches windows.

`docs/contract.md` is everything the two must agree on.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/kellyredding/trellis/main/install.sh | bash
```

Apple Silicon and the current macOS only. On first launch, grant Trellis
Accessibility permission in System Settings → Privacy & Security.

Then `trellis doctor` reports the install, and `trellis update` moves to a
newer release.

## Using the CLI

```bash
trellis windows                      # every window, with IDs
trellis place left-half              # the focused window
trellis place --rect 0.1,0.1,0.8,0.8 --app Safari   # try a shape unsaved
trellis placements add centred --rect 0.1,0.1,0.8,0.8 --group "Full screen"
trellis bind c centred               # ⌃S c now centres the focused window
trellis resolve "l l"                # what a chord does, and whether it waits
```

Every command takes `--json`.

## Config

`~/.trellis/config.json`, or `TRELLIS_CONFIG`. It may be a symlink — for
example into a private dotfiles repository — and edits replace the file it
points to, never the link. Without a config file Trellis uses
`config/starter.json`; `trellis config init --starter` writes it out to edit.

Press ⌃S for layout mode, then a chord. Each placement's `rect` is
`[x, y, width, height]` in fractions of the screen's visible frame (below the
menu bar, beside the Dock), so `"rect": [0, 0, 0.5, 1]` is the left half.
Bindings map a chord to a placement, or to `screen-east` / `screen-west` to
move the window to the next display. The starter binds `h` `l` `k` `j` to the
halves, `i` `o` `,` `.` to the quarters, `ctrl+h` / `ctrl+l` to 60/40,
`cmd+h` / `cmd+l` to 40/60, `return` to the whole screen, and the arrow keys
to the next display.

`groups` names the groups in display order, and every placement names its
`group`; so does each built-in action you bind, under `actions`
(`"actions": {"screen-east": {"group": "Displays"}}`). The app's Bindings tab
shows one section per group, in that order. The starter's groups are Halves,
Corners, 60/40, Full screen and Displays. `trellis groups` adds, renames,
reorders and removes them; `trellis actions set` gives an action its group.

The file is strict JSON. Edit it with the CLI, or by hand followed by
`trellis config validate`; `docs/contract.md` has every key.

## Development

```bash
make check       # CLI gate: lint, build, specs
make app-check   # app gate: build and the sandboxed smoke check
make icon        # redraw the app icon
```

`make check` does not build the app; a change touching both needs both.
Releases are built and published from a Mac with `bin/release`; see
`release-notes/`.

## License

MIT
