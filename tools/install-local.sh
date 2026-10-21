#!/bin/bash
# Builds the apps signed with the team in ~/.config/inkhash/install.env and installs them
# on this Mac and the listed devices. The agent on the Mac runs it once main is green. See ADR 0064.
set -euo pipefail

config="${INKHASH_INSTALL_ENV:-$HOME/.config/inkhash/install.env}"
[[ -f "$config" ]] || { echo "::error::$config fehlt, siehe docs/RELEASE.md." >&2; exit 1; }
# shellcheck disable=SC1090
source "$config"
: "${TEAM:?TEAM in $config setzen}"
DEVICES="${DEVICES:-}"
MAC_TARGETS="${MAC_TARGETS:-/Applications}"
# Depot: internal download page, files builds in /Volumes/Media/Apps (teamCato/apps/depot).
DEPOT_PUBLISH="${DEPOT_PUBLISH:-$(git rev-parse --show-toplevel)/../depot/scripts/publish.sh}"

build=$(git rev-list --count HEAD)
signing=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" CURRENT_PROJECT_VERSION="$build")
warnings=0
warn() { echo "::warning::$*"; warnings=$((warnings + 1)); }
publish() {
  if [[ ! -x "$DEPOT_PUBLISH" ]]; then
    warn "$DEPOT_PUBLISH fehlt, $1 nicht im Depot."
  elif ! "$DEPOT_PUBLISH" "$1"; then
    warn "$1 nicht im Depot abgelegt."
  fi
}

xcodegen generate

xcodebuild -scheme InkhashMac -destination 'platform=macOS' -derivedDataPath .build/install-mac "${signing[@]}" build
app=.build/install-mac/Build/Products/Debug/Inkhash.app
osascript -e 'quit app "Inkhash"' 2>/dev/null || true
for target in $MAC_TARGETS; do
  if [[ ! -d "$target" ]]; then
    warn "$target nicht erreichbar, Mac-App dort nicht installiert."
    continue
  fi
  rm -rf "$target/Inkhash.app"
  # cp, not ditto: ditto fails on the SMB share with "Device error".
  if cp -R -X "$app" "$target/"; then
    touch "$target/Inkhash.app"
    echo "Mac-App $build nach $target"
  else
    warn "Kopieren nach $target fehlgeschlagen."
  fi
done
open /Applications/Inkhash.app 2>/dev/null || true
publish "$app"

if [[ -n "$DEVICES" ]]; then
  xcodebuild -scheme Inkhash -destination 'generic/platform=iOS' -derivedDataPath .build/device "${signing[@]}" CODE_SIGNING_REQUIRED=YES build
  ios_app=.build/device/Build/Products/Debug-iphoneos/Inkhash.app
  publish "$ios_app"
  for device in $DEVICES; do
    if xcrun devicectl device install app --device "$device" "$ios_app"; then
      xcrun devicectl device process launch --device "$device" local.inkhash.ipad || true
      echo "iOS-App $build auf $device"
    else
      warn "Gerät $device gesperrt oder nicht erreichbar."
    fi
  done
fi

echo "Build $build installiert, $warnings Warnung(en)."
