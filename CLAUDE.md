# Trellis

A macOS menu-bar app (`TrellisApp/`, Swift) and a Crystal CLI
(`tools/trellis/`) for keyboard window layout. The app owns everything that
needs the Accessibility permission or the screen; the CLI is the only reader
and writer of the config and talks to the app over a Unix socket.

`docs/contract.md` is the CLI ↔ app contract — paths, key names, the config
export shape, geometry, socket events, exit codes. A change to either side
that touches it changes the contract and both sides in the same commit.

## Branches and releases

- Work lands on `development`. Feature branches
  (`kr/trellis-<feature>NN-<task>`) come off it, and `development`
  fast-forwards to them (`git merge --ff-only`), rebasing first if it moved.
- `main` is the release branch and only ever fast-forwards to
  `development`. Never commit on `main`, not even a version bump.
- **No pull requests and no review loop** in this repository. That is a
  deliberate exception to the general git workflow; do not open PRs here.
- Kelly releases with `bin/release`. **Agents never tag, publish or push a
  release.**
- The version lives only in `VERSION`. The CLI reads it at compile time and
  `bin/package` stamps it into the app; never type a version anywhere else.

## Building and checking

```bash
make check       # CLI: lint + build + specs
make app-check   # app: build + smoke
```

- **`make check` does not build the app.** A change touching both sides
  needs both commands.
- `TrellisApp/project.yml` is the source of truth for the Xcode project,
  which `xcodegen` regenerates on every build and which is not tracked.
  Never run `xcodebuild` directly; never hand-edit the `.xcodeproj`.
- **`TrellisApp/TrellisApp/Models/` is Foundation-only.** The `TrellisSmoke`
  target compiles exactly that directory, which is how geometry, chord
  resolution, key parsing and the config decoding are checked without a
  window server. Anything needing AppKit, Carbon or the Accessibility API
  belongs in `Services/` or `Views/`.
- `fixtures/config.json` and `fixtures/export.json` pin the config export for
  both sides. Never edit them to make one side's check pass.

## Signing and the Accessibility permission

macOS ties the Accessibility grant to the app's signature. **Never sign ad
hoc** for anything installed. Development installs go through the signed
package path (`trellis update --local`), not a symlink
to an Xcode build, or each rebuild can silently revoke the grant and ⌃S stops
working with no error.

## Do not

- Launch Trellis.app or move windows unless asked. Reading (`trellis
  windows`, `screens`, `status`) is always fine.
- Touch `~/.trellis` from specs or checks: every path has an environment
  override (`TRELLIS_ROOT`, `TRELLIS_CONFIG`, `TRELLIS_RUNTIME_DIR`,
  `TRELLIS_SOCKET`, `TRELLIS_BINARY`).
- Commit anyone's personal layouts. The repository ships only
  `config/starter.json`; personal configs live outside it.
