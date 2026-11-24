# The CLI ↔ app contract

Trellis is two programs: the Crystal CLI (`tools/trellis/`) and the Swift
menu-bar app (`TrellisApp/`). They share no code, so everything they must
agree on is written down here. Changing any section means changing both
sides in the same commit.

| Section | Crystal | Swift |
|---|---|---|
| Paths | `tools/trellis/src/trellis/paths.cr` | `TrellisApp/TrellisApp/Models/Paths.swift` |
| Key names | `tools/trellis/src/trellis/keys.cr` | `TrellisApp/TrellisApp/Models/KeyToken.swift` |
| Config export | `tools/trellis/src/trellis/config/export.cr` | `TrellisApp/TrellisApp/Models/ConfigModel.swift` |
| Socket envelope and events | `tools/trellis/src/trellis/socket_client.cr` | `TrellisApp/TrellisApp/Models/Envelope.swift` |

`fixtures/config.json` and `fixtures/export.json` pin the export shape for
both sides: the CLI specs assert that exporting the config yields the JSON
(compared as values, ignoring `path`, with `0` equal to `0.0`), and the app's
smoke check (`make app-smoke`) decodes the JSON. A drift on either side fails
a check. Neither side edits the fixtures to make its own check pass; a
mismatch means the contract changes first.

## Division of labour

- **The app does everything that needs the Accessibility grant or the
  screen:** listing and moving windows, the ⌃S leader, layout mode and its
  key capture, the on-screen label, the menu-bar item. It never reads or
  writes the config file itself.
- **The CLI is the only reader and writer of the config file.** The app gets
  the resolved config by running `trellis config export --json`.
- **Geometry is computed only in the app.** The CLI names placements and
  passes rects; it never computes a frame.

## Paths

Every path can be overridden by an environment variable, so specs and checks
run against temporary directories.

| Path | Default | Override |
|---|---|---|
| Root | `~/.trellis` | `TRELLIS_ROOT` |
| Config | `<root>/config.json` | `TRELLIS_CONFIG` |
| Runtime dir | `<root>/runtime` | `TRELLIS_RUNTIME_DIR` |
| Socket | `<runtime>/trellis.sock` | `TRELLIS_SOCKET` |
| Instance lock | `<socket>.lock` | — |
| Logs | `<runtime>/logs` | — |
| CLI binary (for the app) | `<root>/bin/trellis` | `TRELLIS_BINARY` |

The app creates the runtime directories. The CLI never assumes they exist.

The config path may be a symlink (Kelly's points into his private dotfiles).
Every write resolves the link and replaces the real file, never the link: a
temp file written beside the real file, then renamed over it. Renaming over
the link path itself would replace the link with a regular file.

## Key names

A **key token** is zero or more modifiers and one key, joined by `+`. A
**chord** is one or more key tokens separated by single spaces.

- Modifiers, canonical name first: `ctrl` (`control`), `alt` (`opt`,
  `option`), `shift`, `cmd` (`command`). Canonical order: `ctrl`, `alt`,
  `shift`, `cmd`.
- Keys: `a`–`z`, `0`–`9`; punctuation `` ` `` `-` `=` `[` `]` `\` `;` `'`
  `,` `.` `/`; named keys `return`, `space`, `tab`, `escape`, `delete`,
  `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`,
  `f1`–`f12`.
- Input is case-insensitive; the canonical form is lowercase with modifiers
  in canonical order: `CMD+Ctrl+H` → `ctrl+cmd+h`.
- `escape` may not appear in a binding (it leaves layout mode), and no
  binding's first token may equal the leader.

## Config file (JSON, read and written only by the CLI)

```json
{
  "version": 1,
  "settings": {
    "leader": "ctrl+s",
    "chord_wait_ms": 400,
    "label": {
      "screens": "all",
      "corner": "bottom-right",
      "linger_ms": 1500
    },
    "cheat_sheet": "off",
    "dropdown": {
      "screens": "off"
    }
  },
  "regions": {
    "gutter": {
      "margins": {
        "right": 0.05
      },
      "gap": 0.005
    }
  },
  "placements": {
    "left-half": {
      "rect": [0, 0, 0.5, 1],
      "region": "gutter"
    },
    "maximize": {
      "rect": [0, 0, 1, 1]
    }
  },
  "bindings": {
    "h": "left-half",
    "l l": "right-half-full",
    "right": "screen-east"
  }
}
```

| Setting | Default | Values |
|---|---|---|
| `leader` | `ctrl+s` | one key token with at least one modifier |
| `chord_wait_ms` | `400` | a whole number, `50`–`2000` |
| `label.screens` | `all` | `all`, `main`, `target` |
| `label.corner` | `bottom-right` | `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| `label.linger_ms` | `1500` | a whole number, `0`–`3000`; `0` turns the confirmation off |
| `cheat_sheet` | `off` | `off`, `label`, `dropdown` |
| `dropdown.screens` | `off` | `off`, `all`, `main` |

After a chord typed in layout mode runs, the label stays up for
`label.linger_ms` on the same screens and in the same corner, showing the
chord, what it ran and how that went: `⌃S  h → left-half ✓`, or the window
action's error (`h → left-half: no window is focused`). It is display only:
layout mode has already closed and captures nothing, the leader replaces it at
once with the layout-mode label, and a newer confirmation replaces an older
one and restarts the timer. The socket's `place`, `screen.move` and `chord`
events never show it.

A region's `margins` are fractions of the visible frame, per edge (`top`,
`right`, `bottom`, `left`); its `gap` is a number, or `{"x": 0.005, "y":
0.025}`.

Every key is optional; absent settings take the defaults above. When the
config file does not exist, the CLI uses the starter config embedded in it
(`config/starter.json` in the repository); `trellis config init --starter`
writes that out.

The file is strict JSON (RFC 8259, with no extensions). A file that does not
parse, or repeats a key within one object, is invalid, and the error gives
the line and column. The CLI writes the file with two-space
indentation, the top-level keys in the order above, every other key in its
existing order, arrays of plain values on one line, and a trailing newline.

### Validation

- The top level is an object. Unknown keys are errors at every level
  (`arrangements` included, until arrangements exist), so a typo is reported
  rather than ignored.
- `version` is `1`; a missing `version` reads as `1`.
- Settings: each value is one the table above allows.
- Regions: names match `[a-z0-9][a-z0-9-]*`; each margin and each gap is a
  number in `0…0.5`; per axis the two margins sum to less than `1`; a gap
  object with only `x` or `y` takes `0` for the other.
- Placements: `rect` is `[x, y, w, h]` (or `{x, y, w, h}`) with `x, y ≥ 0`,
  `w, h > 0`, `x + w ≤ 1`, `y + h ≤ 1` (to within `1e-9`); `region`, when
  given, names a defined region. Names match `[a-z0-9][a-z0-9-]*` and may not
  be a built-in action.
- Bindings: each key parses as a chord (modifiers before the key, tokens
  separated by single spaces); each value names a placement or a built-in
  action. Built-in actions: `screen-east`, `screen-west`. Two spellings of
  the same canonical chord (`ctrl+h` and `control+h`) are an error.
- A chord that is also the prefix of a longer chord is a **warning**, not an
  error: it is valid, and it waits. One warning per (prefix, longer chord)
  pair, worded exactly `"<prefix>" is the start of "<longer>", so it waits
  before running`, sorted by prefix then longer chord.

## Config export (`trellis config export --json`)

The normalized config: defaults filled in, regions fully expanded, rects as
objects, chords tokenized and canonical, bindings as a list sorted by
canonical chord.

```json
{
  "version": 1,
  "source": "file",
  "path": "/Users/me/.trellis/config.json",
  "settings": {
    "leader": "ctrl+s",
    "chord_wait_ms": 400,
    "label": { "screens": "all", "corner": "bottom-right", "linger_ms": 1500 },
    "cheat_sheet": "off",
    "dropdown": { "screens": "off" }
  },
  "regions": {
    "gutter": {
      "margins": { "top": 0, "right": 0.05, "bottom": 0, "left": 0 },
      "gap": { "x": 0.005, "y": 0.005 }
    }
  },
  "placements": {
    "left-half": { "rect": { "x": 0, "y": 0, "w": 0.5, "h": 1 }, "region": "gutter" },
    "maximize":  { "rect": { "x": 0, "y": 0, "w": 1, "h": 1 }, "region": null }
  },
  "bindings": [
    { "keys": "h", "chord": ["h"], "target": { "placement": "left-half" }, "prefix": false },
    { "keys": "l l", "chord": ["l", "l"], "target": { "placement": "right-half-full" }, "prefix": false },
    { "keys": "right", "chord": ["right"], "target": { "action": "screen-east" }, "prefix": false }
  ],
  "warnings": []
}
```

- `source` is `"file"` or `"starter"` (no config file exists).
- `path` is the configured path, not the symlink's target.
- `target` has exactly one of `placement` or `action`.
- `prefix` is true when a longer binding begins with this chord.
- An invalid config exits non-zero with the errors on stderr; the app keeps
  its last good config and shows the error.

## Geometry (computed in the app)

All frames are in **global top-left coordinates, in points**: origin at the
top-left of the primary display, y growing downward — the coordinate space of
the Accessibility API and `CGWindowList`. AppKit's `NSScreen` frames are
bottom-left and are converted once, in `Models/`.

For a placement on a screen with visible frame `V` (excludes the menu bar
and the Dock):

1. **Area** `A` = `V` shrunk by the region's margins, each a fraction of
   `V`'s width (left, right) or height (top, bottom).
2. **Slot** = `A.x + rect.x·A.w`, `A.y + rect.y·A.h`, `rect.w·A.w`,
   `rect.h·A.h`.
3. **Gap:** each slot edge strictly inside the area (`rect.x > 0` for the
   left edge, `rect.x + rect.w < 1` for the right, likewise vertically) moves
   inward by half the region's gap, as a fraction of `V`'s width or height.
   Edges on the area boundary do not move.
4. Round to whole points.

Check: `V.w = 1000`, region `{"margins": {"right": 0.05}, "gap": 0.005}`,
rect `[0.5, 0, 0.5, 1]` → `x = 477.5`, `w = 472.5` before rounding — the
Hammerspoon `right` layout.

`screen-east` / `screen-west` move the window to the nearest display whose
frame lies wholly to the east (west), keeping its position and size as
fractions of the visible frame. No wrap-around; no such display is
`not_found`.

## Socket

Unix socket at the socket path. The app listens; the CLI connects, writes one
request line, reads one reply line, and the app closes the connection. This
is Assist Ant's envelope.

Request (one line of JSON, then `\n`):

```json
{"v":1,"event":"place","ts":1716825600,"detail_data":{"placement":"left-half"}}
```

Reply (one line of JSON, then `\n`):

```json
{"ok":true,"data":{ }}
{"ok":false,"error":"Accessibility permission is not granted","code":"not_permitted"}
```

Error codes: `bad_request` (including an unknown placement or region name),
`not_permitted` (no Accessibility grant), `not_found`, `ambiguous`,
`unavailable` (no config loaded yet), `internal`. An `ambiguous` reply
carries `"candidates": [window, …]`. The CLI adds `not_running` to its own
`--json` error output when there is no connection or no reply; the app never
sends it.

Reply details the app settles:
- A bound `chord` that cannot run (no focused window) is an error reply, not
  `"ran": false`; `"ran": false` means the chord is unbound
- A failed `config.reload` is `"ok": true` with `"loaded": false` and the
  error: the request worked, the config did not
- `"main"` in settings means the screen with the menu bar
- Geometry rounds each **edge** to a whole point (not origin and size), so
  neighbouring windows share an edge: 477.5 / 472.5 becomes x 478, w 472

The CLI waits 5 s for a reply. No connection, or no reply, means the app is
not running.

### Window and screen objects

```json
{"id": 4211, "app": "Ghostty", "bundle_id": "com.mitchellh.ghostty", "pid": 812,
 "title": "kx — zsh", "frame": {"x": 0, "y": 38, "w": 945, "h": 1080},
 "screen": 1, "focused": true, "minimized": false}

{"index": 1, "uuid": "37D8832A-…", "name": "Built-in Retina Display",
 "frame": {"x": 0, "y": 0, "w": 1728, "h": 1117},
 "visible_frame": {"x": 0, "y": 38, "w": 1728, "h": 1079},
 "scale": 2, "main": true}
```

`id` is the `CGWindowID`. Screens are indexed from 1, ordered by frame
left to right, then top to bottom.

### Targets

Commands that act on a window take an optional `target` object:

- absent → the focused window
- `{"window_id": 4211}` → that window
- `{"app": "Ghostty", "title": "kx"}` → `app` matches the app name or bundle
  ID (case-insensitive); `title`, if given, is a regular expression matched
  against the title. Exactly one window must match: none is `not_found`,
  several is `ambiguous` with `candidates`.

### Events

| Event | `detail_data` | `data` on success |
|---|---|---|
| `status` | — | `{"version", "pid", "accessibility": bool, "layout_mode": bool, "config": {"path", "source", "loaded": bool, "error": string\|null}}` |
| `screens` | — | `{"screens": [screen…]}` |
| `windows` | `{"app"?, "title"?, "screen"?}` | `{"windows": [window…]}` |
| `place` | `{"target"?, "placement"?, "rect"?, "region"?, "screen"?}` | `{"window": window}` (after) |
| `screen.move` | `{"target"?, "direction": "east"\|"west"}` | `{"window": window}` |
| `chord` | `{"keys": "l l"}` | `{"keys", "target": {…}\|null, "ran": bool}` |
| `config.reload` | — | `{"loaded": bool, "error": string\|null}` |

`place` takes exactly one of `placement` (a name in the loaded config) or
`rect` (`{x, y, w, h}`, with an optional `region` name). `screen` is a screen
index or `"east"` / `"west"`, relative to the window's current screen.
`chord` resolves `keys` as if typed after the leader and runs the result on
the focused window; an unbound chord is `{"target": null, "ran": false}`.

## CLI exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failed (including `bad_request`, `unavailable`, `internal`) |
| 2 | Usage error |
| 3 | The Trellis app is not running (no connection, or no reply) |
| 4 | Accessibility permission not granted (`not_permitted`) |
| 5 | Window or screen target not found, or ambiguous |
