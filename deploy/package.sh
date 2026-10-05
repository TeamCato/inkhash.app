#!/usr/bin/env bash
# Builds the server release package. See ADR 0039.
#   deploy/package.sh <version> [out dir]   ->   <out>/inkhash-server-<version>.tar.gz and .sha256
set -euo pipefail

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version als X.Y.Z angeben, z. B. deploy/package.sh 0.1.0" >&2
  exit 1
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${2:-$root/.build/release}"
out="$(cd "${2:-$root/.build/release}" && pwd)"
name="inkhash-server-$version"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

npm --prefix "$root/Server" ci --no-audit --no-fund
rm -rf "$root/Server/dist"
npm --prefix "$root/Server" run build

pkg="$stage/$name"
mkdir -p "$pkg"
cp -R "$root/Server/dist" "$pkg/dist"
rm -rf "$pkg/dist/test"
# Only what running needs: no scripts, no dev dependencies.
node -e '
  const fs = require("node:fs");
  const source = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const out = { name: source.name, version: process.argv[2], private: true, type: source.type, engines: source.engines };
  fs.writeFileSync(process.argv[3], JSON.stringify(out, null, 2) + "\n");
' "$root/Server/package.json" "$version" "$pkg/package.json"
cp "$root/deploy/linux/install.sh" "$root/deploy/linux/inkhash.service" "$root/deploy/linux/env.example" "$pkg/"
cp "$root/deploy/Caddyfile.example" "$root/docs/DEPLOY.md" "$pkg/"
chmod 0755 "$pkg/install.sh"

COPYFILE_DISABLE=1 tar -C "$stage" -czf "$out/$name.tar.gz" "$name"
(cd "$out" && shasum -a 256 "$name.tar.gz" >"$name.tar.gz.sha256")
echo "$out/$name.tar.gz"
