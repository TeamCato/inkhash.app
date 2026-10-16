#!/usr/bin/env bash
# Runs the Swift client against a real Kennel with the module inkhash: Kennel's own test
# server, on PGlite and a temporary folder, on a free port. See ADR 0067.
# KENNEL_DIR points at a Kennel checkout, by default ../kennel next to this repository.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
kennel="${KENNEL_DIR:-$root/../kennel}"
if [ ! -f "$kennel/package.json" ]; then
  echo "::warning::Kennel nicht gefunden unter $kennel (KENNEL_DIR setzen). Vertragstest übersprungen."
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

INKHASH_CONTRACT_URL="$base" INKHASH_CONTRACT_SETUP="$token" \
  swift test --package-path "$root/Packages/InkhashCore" --filter ContractTests
