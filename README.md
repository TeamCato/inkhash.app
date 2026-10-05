# inkhash

Notizen für iPad, iPhone und Mac. Handschrift auf dem iPad, Text auf beiden, Ablage auf dem eigenen Server. Die Bibliothek durchsucht Text und Handschrift, ohne auf den exakten Wortlaut zu bestehen, und erkennt Schlagwörter.

## Starten

Ohne Server: App bauen und schreiben. Alles bleibt auf dem Gerät. Ein Server ist optional und gleicht Geräte ab, siehe `docs/adr/0017-lokal-zuerst.md`.

Server, nur auf diesem Rechner:

```sh
make server
```

Beim ersten Start schreibt der Server einen Setup-Token und die Adresse der Verwaltung ins Log. Im Browser `http://127.0.0.1:8787/admin` öffnen, mit dem Token den Admin anlegen. Danach gilt der Token nicht mehr. Der Admin ist ein normaler Account für die App und legt auf derselben Seite weitere Accounts mit Startpasswort an. Siehe `docs/adr/0021-admin-im-browser.md`.

In der App unter Server: Adresse `http://127.0.0.1:8787`, dann Name und Passwort. Der Simulator erreicht diese Adresse. Ein echtes iPad braucht die LAN-Adresse:

```sh
make server-lan
```

Container aus dem Quellcode, der Setup-Token steht in `docker compose logs inkhash`:

```sh
docker compose up --build
```

Der Container läuft als Nutzer `node`. Ein Volume aus einer älteren Version gehört noch root und muss einmal umgestellt werden:

```sh
docker compose run --rm -u root inkhash chown -R node:node /data
```

Zu Hause oder im Internet betreiben, mit Release-Paket für Linux oder Image von GHCR, dazu Zugriff von außen und Sicherung: `docs/DEPLOY.md`.


## Bauen

```sh
make test
make generate
make mac
make ipad
```

Das Xcode-Projekt kommt aus `project.yml`. Nicht die `xcodeproj` von Hand ändern.

## Lesen

`AGENTS.md` für die Arbeit am Repo. `docs/PRODUCT.md` für die Grenzen. `docs/adr/0010-suche-und-schlagwoerter.md` für die Suche.
