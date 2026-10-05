# 0039 Der Server kommt als Release und als Image

Status: angenommen

## Entscheidung

Ein Git-Tag `server-vX.Y.Z` im Repository `teamCato/inkhash.app` löst eine GitHub Action aus. Sie testet den Server und veröffentlicht zwei Dinge in derselben Version:

- **Release-Paket** auf GitHub Releases: `inkhash-server-X.Y.Z.tar.gz` mit Prüfsumme. Es enthält das gebaute `dist/`, `package.json`, `install.sh`, die systemd-Unit und eine Caddyfile-Vorlage. Der Server hat keine npm-Abhängigkeiten, das Paket gilt für jede Architektur. Auf dem Host muss Node 24 oder neuer liegen.
- **Container-Image** auf GHCR: `ghcr.io/teamcato/inkhash-server` für `linux/amd64` und `linux/arm64`, mit den Tags `X.Y.Z`, `X.Y`, `X` und `latest`.

Unter Linux installiert `install.sh` den Server als systemd-Dienst: Nutzer `inkhash`, Programm unter `/opt/inkhash/<version>` mit dem Link `current`, Daten unter `/var/lib/inkhash`, Einstellungen in `/etc/inkhash/env`. Ein Update ist dasselbe Skript mit dem neuen Paket; die alte Version bleibt für ein Zurück liegen. Für Docker liegt unter `deploy/docker/` eine Compose-Datei, wahlweise mit Caddy davor.

Der Server lauscht in beiden Fällen auf Loopback oder hinter einem Proxy. Empfohlen ist für den Zugriff von außen ein VPN, sonst ein Reverse-Proxy mit TLS. Siehe `docs/DEPLOY.md` und ADR 0038.

## Warum

Ein Tarball ohne Abhängigkeiten ist klein, prüfbar und für einen Raspberry Pi genauso gut wie für einen Server. Ein `.deb` müsste ein Node 24 voraussetzen, das Debian und Ubuntu nicht mitliefern. Eine einzelne Binärdatei aus Node (SEA) braucht kein Node auf dem Host, ist aber aufwendiger zu bauen und in Node noch nicht stabil. Images für arm64 decken Pi und die meisten NAS ab.

## Nicht

Kein `.deb`, `.rpm`, Homebrew oder Snap. Keine Binärdatei ohne Node, bis es dafür eine neue ADR gibt. Kein TLS im Server. Kein automatisches Update.
