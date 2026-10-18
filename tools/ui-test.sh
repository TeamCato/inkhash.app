#!/usr/bin/env bash
# Runs the UI tests in the iPhone simulator against Kennel's test server, like tools/contract-test.sh.
# Removes the app first, so it starts without servers. KENNEL_DIR as there; without Kennel it is skipped.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
kennel="${KENNEL_DIR:-$root/../kennel}"
if [ ! -f "$kennel/package.json" ]; then
  echo "::warning::Kennel nicht gefunden unter $kennel (KENNEL_DIR setzen). UI-Test übersprungen."
  exit 0
fi
kennel="$(cd "$kennel" && pwd)"
[ -d "$kennel/node_modules" ] || npm --prefix "$kennel" ci --no-audit --no-fund
npm --prefix "$kennel" run build >/dev/null

log="$(mktemp)"
node "$root/tools/contract-kennel.mjs" "$kennel" >"$log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true; rm -f "$log"' EXIT

for _ in $(seq 1 100); do
  grep -q '^kennel: ' "$log" 2>/dev/null && break
  sleep 0.1
done
base="$(sed -n 's/^kennel: //p' "$log")"
token="$(sed -n 's/^setup token: //p' "$log")"
[ -n "$base" ] || { echo "Kennel startete nicht:"; cat "$log"; exit 1; }

device="iPhone Air"
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl uninstall "$device" local.inkhash.ipad 2>/dev/null || true

TEST_RUNNER_INKHASH_UI_URL="$base" TEST_RUNNER_INKHASH_UI_SETUP="$token" \
  xcodebuild -scheme Inkhash -destination "platform=iOS Simulator,name=$device,OS=latest" \
  -derivedDataPath "$root/.build/xcode" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
  -only-testing:InkhashUITests test
