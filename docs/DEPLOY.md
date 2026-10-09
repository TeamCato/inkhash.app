# Server installieren

Der Server ist optional. Er gleicht Geräte ab und speichert Notizen in einem Verzeichnis, sonst nichts. Es gibt ihn als Release-Paket für Linux mit systemd und als Container-Image, beide aus derselben Version:

- Paket: [GitHub Releases](https://github.com/teamCato/inkhash.app/releases), `inkhash-server-X.Y.Z.tar.gz`
- Image: `ghcr.io/teamcato/inkhash-server:X.Y.Z` für amd64 und arm64

Diese Anleitung richtet den Server im Heimnetz ein. Danach erreichen iPad, iPhone und Mac ihn unter `http://<lan-adresse>:8787`, zum Beispiel `http://192.168.1.20:8787`. Der Server spricht nur HTTP. Zugriff von außen ist nicht Teil dieser Anleitung. Wer einen eigenen Reverse-Proxy davor setzt, liest [Hinter einem eigenen Reverse-Proxy](#hinter-einem-eigenen-reverse-proxy).

## Linux mit systemd

Voraussetzungen: systemd, Node 24 oder neuer systemweit installiert (z. B. aus [NodeSource](https://github.com/nodesource/distributions) oder dem Paket der Distribution, nicht über nvm im Home-Verzeichnis).

Version von der Release-Seite nehmen:

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

Standardmäßig lauscht der Server nur auf `127.0.0.1`. Fürs Heimnetz in `/etc/inkhash/env` setzen:

```sh
INKHASH_HOST=0.0.0.0
```

Port ändern: `INKHASH_PORT`. Dann `sudo systemctl restart inkhash`. Läuft eine Firewall, Port 8787 fürs Heimnetz freigeben, z. B. `sudo ufw allow from 192.168.1.0/24 to any port 8787`.

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
for f in compose.yaml env.example; do
  curl -LO https://raw.githubusercontent.com/teamCato/inkhash.app/main/deploy/docker/$f
done
cp env.example .env
mkdir -p data && sudo chown 1000:1000 data
```

Fürs Heimnetz in `.env` setzen:

```sh
INKHASH_BIND=0.0.0.0
```

Dann starten:

```sh
docker compose up -d
docker compose logs inkhash
```

Anderer Port auf dem Host: in `compose.yaml` die linke Seite von `8787:8787` ändern.

Der Container läuft als Nutzer `node` (UID 1000), mit schreibgeschütztem Dateisystem und ohne Capabilities. Die Notizen liegen in `./data`. Gehört das Verzeichnis jemand anderem, beendet sich der Server mit `cannot write /data`. Docker veröffentlicht Ports an ufw und firewalld vorbei; ohne `INKHASH_BIND=0.0.0.0` ist der Port nur auf dem Rechner selbst erreichbar.

**Version festhalten:** `INKHASH_VERSION=0.1` in `.env` bekommt Fehlerbehebungen, aber keine neue Minor-Version. **Update:** `docker compose pull && docker compose up -d`.

Auf einem NAS (Synology, QNAP) gilt dasselbe: `data` muss UID 1000 gehören.

## Einrichten

LAN-Adresse des Servers herausfinden, z. B. mit `hostname -I` (Linux) oder in der Geräteliste des Routers. Im Router am besten eine feste Adresse für den Server vergeben, sonst ändert sie sich irgendwann und die App findet ihn nicht mehr.

Beim ersten Start ohne Account schreibt der Server einen Setup-Token ins Log:

```
not set up yet: open http://<this host>:8787/admin
setup token: …
```

Linux: `journalctl -u inkhash | grep -A1 'not set up'`. Docker: `docker compose logs inkhash`. Der Token gilt bis zum nächsten Neustart; danach steht ein neuer im Log.

Im Browser `http://<lan-adresse>:8787/admin` öffnen, Token, Name und Passwort eingeben. Das ist der Admin. Er legt auf derselben Seite weitere Accounts mit Startpasswort an.

In der App unter Server die Adresse `http://<lan-adresse>:8787` eintragen, dann Name und Passwort. Beim ersten Mal fragt iOS nach Zugriff aufs lokale Netzwerk; ohne Erlaubnis erreicht die App den Server nicht (Einstellungen → Datenschutz → Lokales Netzwerk).

Für reines HTTP nur eine IP-Adresse oder einen Namen auf `.local` verwenden. Andere Namen (`inkhash.home.arpa`, `nas.lan`) blockiert iOS ohne HTTPS (App Transport Security). Wer solche Namen will, braucht einen eigenen Reverse-Proxy mit TLS davor.

**Läuft es?** `curl http://<lan-adresse>:8787/v1/health` von einem anderen Rechner im Netz. Kommt keine Antwort: lauscht der Server auf `0.0.0.0` (`INKHASH_HOST` bzw. `INKHASH_BIND`), ist der Port in der Firewall frei?

Im Heimnetz gehen Token und Passwort unverschlüsselt über das Netz. Wer dem eigenen WLAN nicht traut, richtet den Admin über einen SSH-Tunnel ein (`ssh -L 8787:127.0.0.1:8787 server`, dann `http://127.0.0.1:8787/admin`).

## Hinter einem eigenen Reverse-Proxy

Der Server sieht hinter einem Proxy nur dessen Adresse. Dann teilen sich alle Clients einen Zähler für Fehlversuche, und 30 falsche Anmeldungen von irgendwem sperren 15 Minuten lang alle. Damit der Server die echte Adresse aus `X-Forwarded-For` nimmt, muss der Proxy in `INKHASH_TRUSTED_PROXIES` stehen: Adressen oder Netze, durch Komma getrennt, z. B. `127.0.0.1,::1` oder `172.31.87.0/24`. Der Proxy muss `X-Forwarded-For` setzen.

| Wo der Proxy läuft | Linux (`/etc/inkhash/env`) | Docker (`.env`) |
| --- | --- | --- |
| auf demselben Rechner | `127.0.0.1,::1` | `172.31.87.1`, der Standard |
| als Container im Netz `inkhash` der Compose-Datei | – | seine Adresse dort, oder `172.31.87.0/24` |
| auf einem anderen Rechner | seine LAN-Adresse | seine LAN-Adresse |

Welche Adresse wirklich ankommt, sagt der Server selbst: Schickt ein nicht eingetragener Absender `X-Forwarded-For`, steht einmal im Log `<adresse> sends X-Forwarded-For but is not in INKHASH_TRUSTED_PROXIES`. Diese Adresse eintragen und neu starten (`sudo systemctl restart inkhash` bzw. `docker compose up -d`). Probe: Eine falsche Anmeldung über den Proxy zeigt danach `auth failed /v1/session 401 from <client-adresse>` und nicht die Adresse des Proxys.

Nur Proxys eintragen, die man selbst betreibt. Wer in der Liste steht, darf dem Server jede Client-Adresse nennen.

## Was der Betreiber sieht

Notizen liegen unverschlüsselt im Datenverzeichnis. Wer Zugriff auf die Maschine hat, kann sie lesen. Der Admin vergibt die Startpasswörter. Jeder Account ändert sein Passwort danach in der App selbst (ADR 0050). Wer Accounts für andere anlegt, sollte ihnen das sagen.

## Sichern und Wiederherstellen

Sichern ist das Kopieren des Datenverzeichnisses (`/var/lib/inkhash` oder `./data`), auch im laufenden Betrieb: Notizdateien werden atomar geschrieben, das Änderungsprotokoll wird beim Start repariert. Zum Beispiel mit restic:

```sh
sudo restic -r /mnt/backup/inkhash backup /var/lib/inkhash
```

Wiederherstellen: Dienst stoppen, Verzeichnis ersetzen, Rechte prüfen (`inkhash` bzw. UID 1000, Modus `0700`), starten. Geräte gleichen danach alles einmal ab und laden fehlende Notizen wieder hoch.

**Gelöschten Workspace zurückholen.** Ein in der App gelöschter Workspace liegt unter `spaces/<account-id>/deleted/<workspace-id>-<zeit>` (ADR 0045). Ordner zurück nach `spaces/<account-id>/workspaces/<workspace-id>` verschieben und in `spaces/<account-id>/workspaces.json` einen Eintrag `{ "id": "<workspace-id>", "name": "…" }` ergänzen. Ohne Neustart sichtbar. Für `main` (`deleted/main-<zeit>`): `notes`, `blobs` und `changes.jsonl` zurück nach `spaces/<account-id>/` verschieben, in `spaces/<account-id>/main.json` das Feld `deletedAt` entfernen und den Server neu starten. Sind sie sicher nicht mehr nötig, lassen sich die Ordner unter `deleted/` löschen.

**Gelöschten Account zurückholen.** Ein auf `/admin` gelöschter Account liegt unter `deleted-accounts/<account-id>-<zeit>` im Datenverzeichnis (ADR 0046). `identity.json` von dort nach `identities/<name>.json` legen (der Name darf inzwischen nicht neu vergeben sein), den übrigen Ordner nach `spaces/<account-id>` verschieben und den Server neu starten.

## Gerät verloren, Passwort vergessen

Ein Admin setzt auf `/admin` unter „Bearbeiten“ ein neues Passwort; das beendet auch alle Sitzungen des Accounts, etwa die eines verlorenen Geräts (ADR 0046). Nur wer das Passwort des letzten Admins vergessen hat, braucht das Datenverzeichnis. Die Befehle unten sind für Linux; unter Docker statt `sudo -u inkhash` ein `docker compose exec inkhash` davor und `/data` statt `/var/lib/inkhash`.

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
| `INKHASH_TRUSTED_PROXIES` | leer, unter Docker `172.31.87.1` | Proxys, deren `X-Forwarded-For` gilt. Siehe [Hinter einem eigenen Reverse-Proxy](#hinter-einem-eigenen-reverse-proxy) |
