#!/usr/bin/env bash
# Installs or updates the inkhash server as a systemd service. Run from the unpacked release:
#   sudo ./install.sh
# Program in /opt/inkhash/<version>, data in /var/lib/inkhash, settings in /etc/inkhash/env.
# See docs/DEPLOY.md and ADR 0039.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix=/opt/inkhash
config=/etc/inkhash
unit=/etc/systemd/system/inkhash.service

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "bitte als root ausführen: sudo ./install.sh"
command -v systemctl >/dev/null || fail "systemd fehlt. Ohne systemd: Docker, siehe DEPLOY.md"
[ -f "$here/dist/inkhashd.js" ] || fail "dist/inkhashd.js fehlt. Aus dem entpackten Release-Paket starten"

version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$here/package.json" | head -n 1)"
[ -n "$version" ] || fail "keine Version in package.json"

node="$(command -v node || true)"
[ -n "$node" ] || fail "Node fehlt. Nötig ist Node 24 oder neuer, siehe DEPLOY.md"
major="$("$node" -p 'process.versions.node.split(".")[0]')"
[ "$major" -ge 24 ] || fail "Node $major gefunden, nötig ist 24 oder neuer"
node="$(readlink -f "$node")"
case "$node" in
  /home/* | /root/*) fail "Node liegt unter $node. Der Dienst darf nicht in Home-Verzeichnisse: Node systemweit installieren" ;;
esac

if ! id inkhash >/dev/null 2>&1; then
  nologin="$(command -v nologin || echo /bin/false)"
  useradd --system --user-group --home-dir /var/lib/inkhash --no-create-home --shell "$nologin" inkhash
fi

first=no
[ -e "$unit" ] || first=yes

target="$prefix/$version"
install -d -m 0755 "$prefix"
rm -rf "$target.new"
install -d -m 0755 "$target.new"
cp -R "$here/dist" "$here/package.json" "$target.new/"
chown -R root:root "$target.new"
chmod -R u=rwX,go=rX "$target.new"
rm -rf "$target"
mv "$target.new" "$target"
ln -sfn "$target" "$prefix/current"

install -d -m 0755 "$config"
[ -f "$config/env" ] || install -m 0644 "$here/env.example" "$config/env"

sed "s|@NODE@|$node|" "$here/inkhash.service" >"$unit.new"
chmod 0644 "$unit.new"
mv "$unit.new" "$unit"
systemctl daemon-reload
systemctl enable inkhash >/dev/null 2>&1
systemctl restart inkhash

echo "inkhash $version läuft als Dienst inkhash. Einstellungen: $config/env"
if [ "$first" = yes ]; then
  sleep 1
  echo "Setup-Token und Adresse der Verwaltung:"
  echo "  journalctl -u inkhash | grep -A1 'not set up'"
fi
others="$(find "$prefix" -mindepth 1 -maxdepth 1 -type d ! -name "$version" -printf '%f ' 2>/dev/null || true)"
[ -z "$others" ] || echo "Ältere Versionen unter $prefix: $others"
