# Server betreiben

Der Server ist optional. Er gleicht Geräte ab und speichert Notizen in einem Verzeichnis, sonst nichts (ADR 0017). Es gibt ihn als Release-Paket für Linux mit systemd und als Container-Image, beide aus derselben Version (ADR 0039):

- Paket: [GitHub Releases](https://github.com/teamCato/inkhash.app/releases), `inkhash-server-X.Y.Z.tar.gz`
- Image: `ghcr.io/teamcato/inkhash-server:X.Y.Z` für amd64 und arm64

Der Server spricht nur HTTP und lauscht standardmäßig auf `127.0.0.1:8787`. Für Zugriff von außen gehört etwas davor, das TLS kann. Siehe [Zugriff von außen](#zugriff-von-außen).

## Welcher Weg

| Ziel | Weg |
| --- | --- |
| Nur im Heimnetz | `INKHASH_HOST=0.0.0.0` (Linux) oder `INKHASH_BIND=0.0.0.0` (Docker). Die App verbindet sich mit `http://<lan-adresse>:8787` |
| Auch unterwegs, empfohlen | VPN, am einfachsten Tailscale mit `tailscale serve`. Kein offener Port, gültiges Zertifikat, geht auch hinter DS-Lite |
| Öffentlich unter eigener Domain | Caddy davor, Ports 80 und 443 freigeben. Vorher die [Checkliste](#checkliste-vor-dem-öffnen) |

## Linux mit systemd

Voraussetzungen: systemd, Node 24 oder neuer systemweit installiert (z. B. aus [NodeSource](https://github.com/nodesource/distributions) oder dem Paket der Distribution, nicht über nvm im Home-Verzeichnis).

```sh
VERSION=0.1.0
curl -LO https://github.com/teamCato/inkhash.app/releases/download/server-v$VERSION/inkhash-server-$VERSION.tar.gz
curl -LO https://github.com/teamCato/inkhash.app/releases/download/server-v$VERSION/inkhash-server-$VERSION.tar.gz.sha256
sha256sum -c inkhash-server-$VERSION.tar.gz.sha256
tar xzf inkhash-server-$VERSION.tar.gz
cd inkhash-server-$VERSION
sudo ./install.sh
```

`install.sh` legt den Systemnutzer `inkhash` an, kopiert das Programm nach `/opt/inkhash/<version>`, setzt `/opt/inkhash/current` darauf und startet den Dienst `inkhash`. Daten liegen in `/var/lib/inkhash` (nur für `inkhash` lesbar), Einstellungen in `/etc/inkhash/env`. Die Datei wird beim ersten Mal angelegt und danach nie überschrieben.

| Befehl | Wofür |
| --- | --- |
| `systemctl status inkhash` | läuft er? |
| `journalctl -u inkhash -f` | Log |
| `sudo systemctl restart inkhash` | nach Änderungen an `/etc/inkhash/env` |

**Update:** neues Paket laden, entpacken, `sudo ./install.sh`. Die alte Version bleibt unter `/opt/inkhash` liegen.
**Zurück:** `sudo ln -sfn /opt/inkhash/<alte-version> /opt/inkhash/current && sudo systemctl restart inkhash`.
**Entfernen:** `sudo systemctl disable --now inkhash`, dann `/etc/systemd/system/inkhash.service`, `/opt/inkhash` und `/etc/inkhash` löschen. `/var/lib/inkhash` enthält die Notizen.

## Docker

```sh
mkdir inkhash && cd inkhash
for f in compose.yaml env.example Caddyfile; do
  curl -LO https://raw.githubusercontent.com/teamCato/inkhash.app/main/deploy/docker/$f
done
cp env.example .env
mkdir -p data && sudo chown 1000:1000 data
docker compose up -d
docker compose logs inkhash
```

Der Container läuft als Nutzer `node` (UID 1000), mit schreibgeschütztem Dateisystem und ohne Capabilities. Die Notizen liegen in `./data`. Gehört das Verzeichnis jemand anderem, beendet sich der Server mit `cannot write /data` (P-023).

Der Port ist nur an `127.0.0.1` gebunden. Docker veröffentlicht Ports an ufw und firewalld vorbei; `INKHASH_BIND=0.0.0.0` in `.env` öffnet ihn fürs Heimnetz.

**Version festhalten:** `INKHASH_VERSION=0.1` in `.env` bekommt Fehlerbehebungen, aber keine neue Minor-Version. **Update:** `docker compose pull && docker compose up -d`.

**Mit Caddy davor:** In `.env` `INKHASH_DOMAIN=notizen.example.org` setzen, dann `docker compose --profile caddy up -d`. Caddy holt das Zertifikat selbst und braucht dafür die Ports 80 und 443.

Auf einem NAS (Synology, QNAP) gilt dasselbe: `data` muss UID 1000 gehören.

## Einrichten

Beim ersten Start ohne Account schreibt der Server einen Setup-Token ins Log:

```
not set up yet: open http://127.0.0.1:8787/admin
setup token: …
```

Im Browser `/admin` öffnen, Token, Name und Passwort eingeben. Das ist der Admin. Er legt auf derselben Seite weitere Accounts mit Startpasswort an (ADR 0021).

Einrichten, bevor der Server nach außen offen ist, und nicht über reines HTTP aus dem Internet: Token und Passwort gingen sonst im Klartext. Läuft der Server auf einer anderen Maschine nur an `127.0.0.1`, reicht ein SSH-Tunnel:

```sh
ssh -L 8787:127.0.0.1:8787 server
# dann im eigenen Browser: http://127.0.0.1:8787/admin
```

In der App unter Server die Adresse eintragen (`https://…` von außen, `http://<lan-adresse>:8787` im Heimnetz), dann Name und Passwort.

## Zugriff von außen

### Tailscale (empfohlen)

Tailscale auf dem Server und auf iPad, iPhone, Mac. In der Tailscale-Verwaltung MagicDNS und HTTPS-Zertifikate einschalten. Dann auf dem Server:

```sh
sudo tailscale serve --bg http://127.0.0.1:8787
```

Die App verbindet sich mit `https://<maschine>.<tailnet>.ts.net`. Kein Port im Router, keine Domain. Für Linux zusätzlich `INKHASH_TRUSTED_PROXIES=127.0.0.1,::1` in `/etc/inkhash/env`; die Docker-Compose-Datei vertraut dem Host schon.

### Caddy mit eigener Domain

1. Eine Domain oder DynDNS-Adresse, die auf den Anschluss zeigt.
2. Im Router die Ports 80 und 443 auf den Server weiterleiten. **Nicht** 8787.
3. Linux: Caddy installieren, `Caddyfile.example` aus dem Paket nach `/etc/caddy/Caddyfile`, den Namen einsetzen, `INKHASH_TRUSTED_PROXIES=127.0.0.1,::1` in `/etc/inkhash/env`, beide Dienste neu starten. Docker: `--profile caddy`, siehe oben.

**DS-Lite** (viele Kabel- und Glasfaseranschlüsse): Von außen gibt es keine eigene IPv4-Adresse, Portfreigaben für IPv4 gehen nicht. Entweder nur über IPv6 (AAAA-Eintrag, Freigabe für IPv6 im Router) oder Tailscale.

### Andere Proxys

- **nginx** nimmt standardmäßig nur 1 MB an, Blobs haben bis zu 20 MiB: `client_max_body_size 25m;`. Dazu `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` (P-048).
- **Cloudflare Tunnel** funktioniert ohne Portfreigabe, aber TLS endet bei Cloudflare: Cloudflare kann die Notizen lesen.

Jeder Proxy muss in `INKHASH_TRUSTED_PROXIES` stehen, sonst sieht der Server alle Clients unter der Adresse des Proxys, und 30 Fehlversuche von irgendwem sperren für 15 Minuten alle Anmeldungen (ADR 0038). Der Server meldet im Log einmal, wenn ein nicht vertrauter Absender `X-Forwarded-For` schickt.

## Checkliste vor dem Öffnen

- [ ] Admin eingerichtet, Setup-Token damit verbraucht
- [ ] Nur HTTPS von außen, Port 8787 nicht im Router freigegeben
- [ ] `INKHASH_TRUSTED_PROXIES` gesetzt. Probe: eine falsche Anmeldung von außen zeigt im Log `auth failed /v1/session 401 from <deine öffentliche Adresse>`, nicht die des Proxys
- [ ] Lange Passwörter. Namen sind nicht geheim: acht Fehlversuche sperren einen Namen 15 Minuten
- [ ] Sicherung eingerichtet

Optional fail2ban mit diesem Filter auf das Log des Dienstes:

```ini
[Definition]
failregex = ^.*auth failed /v1/(setup|session) \d+ from <HOST>$
```

## Was der Betreiber sieht

Notizen liegen unverschlüsselt im Datenverzeichnis. Wer Zugriff auf die Maschine hat, kann sie lesen. Der Admin vergibt die Startpasswörter, und es gibt noch keinen Weg, das eigene Passwort zu ändern. Wer Accounts für andere anlegt, sollte ihnen das sagen.

## Sichern und Wiederherstellen

Sichern ist das Kopieren des Datenverzeichnisses (`/var/lib/inkhash` oder `./data`), auch im laufenden Betrieb: Notizdateien werden atomar geschrieben, das Änderungsprotokoll wird beim Start repariert (ADR 0015). Zum Beispiel mit restic:

```sh
sudo restic -r /mnt/backup/inkhash backup /var/lib/inkhash
```

Wiederherstellen: Dienst stoppen, Verzeichnis ersetzen, Rechte prüfen (`inkhash` bzw. UID 1000, Modus `0700`), starten. Geräte gleichen danach alles einmal ab und laden fehlende Notizen wieder hoch (API.md, „Änderungen“).

## Gerät verloren, Passwort vergessen

Dafür gibt es noch keinen Befehl. Bis dahin von Hand im Datenverzeichnis. Die Befehle unten sind für Linux; unter Docker statt `sudo -u inkhash` ein `docker compose exec inkhash` davor und `/data` statt `/var/lib/inkhash`.

**Alle Sitzungen eines Accounts beenden.** Die Account-ID steht in `identities/<name>.json`. Wirkt sofort, ohne Neustart.

```sh
sudo -u inkhash sh -c 'grep -l "\"accountId\":\"<account-id>\"" /var/lib/inkhash/sessions/*.json | xargs -r rm'
```

**Neues Passwort setzen.** Ersetzt den Hash in der Datei des Accounts. Danach sind bestehende Sitzungen weiter gültig; bei Bedarf wie oben beenden.

```sh
sudo -u inkhash node -e '
  const crypto = require("node:crypto"), fs = require("node:fs");
  const [file, password] = process.argv.slice(1);
  const salt = crypto.randomBytes(16);
  const digest = crypto.pbkdf2Sync(password, salt, 600000, 32, "sha256");
  const identity = JSON.parse(fs.readFileSync(file, "utf8"));
  identity.passwordHash = `pbkdf2_sha256$600000$${salt.toString("hex")}$${digest.toString("hex")}`;
  fs.writeFileSync(file + ".tmp", JSON.stringify(identity), { mode: 0o600 });
  fs.renameSync(file + ".tmp", file);
' /var/lib/inkhash/identities/<name>.json '<neues passwort>'
```

Das Passwort steht danach in der Shell-History; `history -d` oder ein führendes Leerzeichen hilft.

## Umgebungsvariablen

| Variable | Standard | Bedeutung |
| --- | --- | --- |
| `INKHASH_HOST` | `127.0.0.1`, im Image `0.0.0.0` | Adresse, auf der der Server lauscht |
| `INKHASH_PORT` | `8787` | Port |
| `INKHASH_DATA` | `/data`, unter systemd `/var/lib/inkhash` | Datenverzeichnis |
| `INKHASH_TRUSTED_PROXIES` | leer | Adressen und Netze (`127.0.0.1,::1`, `172.31.87.0/24`), deren `X-Forwarded-For` gilt. ADR 0038 |

## Ein Release machen

```sh
git tag server-v0.1.0
git push origin server-v0.1.0
```

Die Action `Server release` testet, baut das Paket (`deploy/package.sh`), schiebt das Image nach GHCR und legt das GitHub-Release an. Lokal baut `make server-package VERSION=0.1.0` dasselbe Paket nach `.build/release/`. Beim ersten Mal das Paket `inkhash-server` auf GitHub unter Packages auf öffentlich stellen, sonst braucht `docker pull` eine Anmeldung.
