#!/usr/bin/env bash
# Installs or updates Trellis: the trellis CLI and Trellis.app.
#
#   curl -fsSL https://raw.githubusercontent.com/kellyredding/trellis/main/install.sh | bash
#
# `trellis update` runs this same script. Options (after `bash -s --` when piped):
#
#   --version X.Y.Z   Install that release instead of the latest
#   --from ARCHIVE    Install a local archive written by bin/package
#   --preview         Show what would change, change nothing
#   --force           Reinstall even when already up to date
#   --no-register     Skip Launch Services registration (sandboxed tests)
#
# Never launches, quits or restarts Trellis.

# One compound command, so bash reads all of it before running any: piped in,
# a truncated download or a command that reads stdin would otherwise cut the
# script short partway through an install.
{
set -euo pipefail

REPO="kellyredding/trellis"
ASSET="trellis-darwin-arm64.tar.gz"
IDENTITY="Trellis Release Signing"
MIN_MACOS=26
TRELLIS_HOME="${TRELLIS_ROOT:-$HOME/.trellis}"
BIN_DIR="$TRELLIS_HOME/bin"
LOCAL_BIN="$HOME/.local/bin"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/Trellis.app"
INSTALLED_MANIFEST="$TRELLIS_HOME/installed-manifest.json"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

version=""
from=""
preview=false
force=false
register=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:?--version needs X.Y.Z}"; version="${version#v}"; shift ;;
    --from) from="${2:?--from needs an archive path}"; shift ;;
    --preview|preview) preview=true ;;
    --force|force) force=true ;;
    --no-register) register=false ;;
    # Piped in, $0 is the shell rather than this file.
    -h|--help|help) if [[ -f "$0" ]]; then sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
                    else echo "See https://github.com/$REPO/blob/main/install.sh"; fi; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done
if [[ -n "$from" && -n "$version" ]]; then
  echo "install.sh: --from installs that archive; it cannot be combined with --version" >&2
  exit 2
fi

if [[ -t 1 ]]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; NC=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; NC=""; fi
say() { printf '%s\n' "$*"; }
step() { printf '  %s\n' "$*"; }
die() { printf '%sinstall.sh: %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

# --- This Mac ----------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] \
  || die "Trellis releases are built for Apple Silicon Macs only; this is $(uname -s) on $(uname -m)."
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= MIN_MACOS )) || die "Trellis needs macOS $MIN_MACOS or later; this Mac runs $macos."

work="$(mktemp -d)"
installed_ok=false
# shellcheck disable=SC2329 # run by the trap below
tr_cleanup() {
  if $installed_ok || $preview; then rm -rf "${work:?}"
  else printf 'Working files kept for inspection: %s\n' "$work" >&2; fi
}
trap tr_cleanup EXIT

# --- Fetch -------------------------------------------------------------------

if [[ -n "$from" ]]; then
  [[ -f "$from" ]] || die "no archive at $from"
  cp "$from" "$work/$ASSET"
  # Renamed to the fixed name, so an archive saved under another name still
  # checks against its own checksum file.
  if [[ -f "$from.sha256" ]]; then
    sed "s/[^ ]*$/$ASSET/" "$from.sha256" > "$work/$ASSET.sha256"
  fi
  source_label="$from"
else
  if [[ -n "$version" ]]; then
    base="https://github.com/$REPO/releases/download/v$version"
  else
    base="https://github.com/$REPO/releases/latest/download"
  fi
  # curl rather than a browser download: curl sets no quarantine flag, which
  # is what lets a self-signed Trellis.app open without a Gatekeeper prompt.
  curl -fsSL "$base/$ASSET" -o "$work/$ASSET" </dev/null \
    || die "could not download $base/$ASSET${version:+ (is v$version a Trellis release?)}"
  curl -fsSL "$base/$ASSET.sha256" -o "$work/$ASSET.sha256" </dev/null \
    || die "could not download the checksum for $ASSET"
  source_label="$base"
fi

if [[ -f "$work/$ASSET.sha256" ]]; then
  (cd "$work" && shasum -a 256 -c "$ASSET.sha256" >/dev/null) \
    || die "checksum mismatch for $ASSET; nothing was installed"
elif [[ -z "$from" ]]; then
  die "no checksum for $ASSET; nothing was installed"
fi

mkdir -p "$work/unpacked"
tar -xzf "$work/$ASSET" -C "$work/unpacked" || die "could not unpack $ASSET"
pkg="$work/unpacked/trellis"
[[ -f "$pkg/manifest.json" && -f "$pkg/bin/trellis" && -d "$pkg/Trellis.app" ]] \
  || die "$ASSET is not a Trellis release archive"

# macOS ties the Accessibility grant to the app's signature, so an app signed
# any other way would silently lose it: refused before anything is replaced.
for target in "$pkg/Trellis.app" "$pkg/bin/trellis"; do
  codesign --verify --strict "$target" 2>/dev/null \
    || die "$(basename "$target") in $ASSET does not verify; nothing was installed"
  signature="$(codesign -dv --verbose=2 "$target" 2>&1)"
  [[ "$signature" == *$'\n'"Authority=$IDENTITY"$'\n'* ]] \
    || die "$(basename "$target") in $ASSET is not signed by $IDENTITY, so Trellis would lose its Accessibility permission. Package it with bin/package (--sign op); nothing was installed"
done

manifest_field() { sed -n "s/^  \"$1\": \"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}$/\1/p" "$2" | sed -n 1p; }
new_version="$(manifest_field version "$pkg/manifest.json")"
new_commit="$(manifest_field commit "$pkg/manifest.json")"
new_dirty="$(manifest_field dirty "$pkg/manifest.json")"
if [[ -f "$INSTALLED_MANIFEST" ]]; then
  cur_version="$(manifest_field version "$INSTALLED_MANIFEST")"
  cur_commit="$(manifest_field commit "$INSTALLED_MANIFEST")"
  cur_dirty="$(manifest_field dirty "$INSTALLED_MANIFEST")"
elif [[ -x "$BIN_DIR/trellis" ]]; then
  cur_version="unknown (installed from source)"; cur_commit=""; cur_dirty=""
else
  cur_version="not installed"; cur_commit=""; cur_dirty=""
fi
first_app=false
[[ -e "$APP" || -L "$APP" ]] || first_app=true

describe() { printf '%s' "$1"; [[ -n "$2" ]] && printf ' (%s%s)' "$2" "$([[ "$3" == true ]] && echo ', uncommitted changes')"; }

# A release is up to date when it is the same commit with no local edits.
# --from always installs, because a local archive is installed on purpose.
if [[ -z "$from" ]] && ! $force && ! $preview \
   && [[ -n "$cur_commit" && "$cur_commit" == "$new_commit" && "$cur_dirty" != "true" ]]; then
  say "${GREEN}Trellis is up to date: $(describe "$cur_version" "$cur_commit" "$cur_dirty")${NC}"
  installed_ok=true
  exit 0
fi

say "${BOLD}$([[ "$cur_version" == "not installed" ]] && echo Installing || echo Updating) Trellis${NC}"
step "From:      $source_label"
step "Installed: $(describe "$cur_version" "$cur_commit" "$cur_dirty")"
step "New:       $(describe "$new_version" "$new_commit" "$new_dirty")"
step "CLI:       $BIN_DIR/trellis (linked into $LOCAL_BIN)"
step "App:       $APP"
step "Signed by: $IDENTITY"

if $preview; then
  say ""
  say "Preview only: nothing was changed. Run without --preview to install."
  exit 0
fi
say ""

# --- Install -----------------------------------------------------------------

mkdir -p "$BIN_DIR" "$LOCAL_BIN" "$APP_DIR"

# A new file moved over the old one, rather than copied onto it, so a binary
# that is running keeps its pages and macOS sees a fresh signature.
install -m 755 "$pkg/bin/trellis" "$BIN_DIR/.trellis.new"
mv -f "$BIN_DIR/.trellis.new" "$BIN_DIR/trellis"
# Replaces a plain file a source install may have left here, too.
ln -sfn "$BIN_DIR/trellis" "$LOCAL_BIN/trellis"
step "Installed trellis"

# Swapped by rename: a running Trellis keeps running from its old bundle, and
# the next launch opens the new one. A link to a build folder is removed.
rm -rf "${APP:?}.new" "${APP:?}.old"
ditto "$pkg/Trellis.app" "$APP.new"
if [[ -L "$APP" ]]; then
  rm "${APP:?}"
elif [[ -e "$APP" ]]; then
  mv "$APP" "$APP.old"
fi
mv "$APP.new" "$APP"
rm -rf "${APP:?}.old"
step "Installed Trellis.app"

if $register; then
  "$LSREGISTER" -f "$APP"
  # Copies left in an Xcode build folder share the bundle id, so leave the
  # installed one the only Trellis.app registered.
  while IFS= read -r stale; do
    "$LSREGISTER" -u "$stale" 2>/dev/null || true
    step "Unregistered $stale"
  done < <("$LSREGISTER" -dump 2>/dev/null \
             | sed -n 's/^path: *\(.*\/Build\/Products\/[^/]*\/Trellis\.app\) (0x[0-9a-f]*)$/\1/p' \
             | sort -u)
fi

cp "$pkg/manifest.json" "$INSTALLED_MANIFEST"
installed_ok=true

# --- Next steps --------------------------------------------------------------

say ""
say "${GREEN}Trellis $(describe "$new_version" "$new_commit" "$new_dirty") is installed.${NC}"
case ":$PATH:" in
  *":$LOCAL_BIN:"*) ;;
  *) say "Add $LOCAL_BIN to your PATH to use trellis." ;;
esac
# Forget where trellis was found before the install, so this looks again.
hash -r
on_path="$(command -v trellis || true)"
if [[ -n "$on_path" && "$on_path" != "$LOCAL_BIN/trellis" && "$on_path" != "$BIN_DIR/trellis" ]]; then
  say "$on_path comes first on your PATH and is not this install; remove it."
fi
if $first_app; then
  say "Open Trellis with: open \"$APP\""
  say "It asks for the Accessibility permission on first launch; grant it in System Settings."
else
  say "A running Trellis keeps the old build until you restart it; restart it when you're ready to switch."
fi
exit 0
}
