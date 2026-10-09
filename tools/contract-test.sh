#!/usr/bin/env bash
# Runs the Swift client against the real server: a fresh data directory, a free port,
# the setup token from the log. See ADR 0052 and docs/API.md.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
data="$(mktemp -d)"
log="$data/server.log"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"

INKHASH_DATA="$data/data" INKHASH_HOST=127.0.0.1 INKHASH_PORT="$port" node "$root/Server/dist/inkhashd.js" 2>"$log" &
server=$!
trap 'kill $server 2>/dev/null || true; rm -rf "$data"' EXIT

for _ in $(seq 1 50); do
  grep -q '^setup token: ' "$log" 2>/dev/null && break
  sleep 0.1
done
token="$(sed -n 's/^setup token: //p' "$log")"
[ -n "$token" ] || { echo "server did not start:"; cat "$log"; exit 1; }

INKHASH_CONTRACT_URL="http://127.0.0.1:$port" INKHASH_CONTRACT_SETUP="$token" \
  swift test --package-path "$root/Packages/InkhashCore" --filter ContractTests
