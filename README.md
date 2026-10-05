# inkhash

Notizen für iPad, iPhone und Mac. Handschrift auf dem iPad, Text auf beiden, Ablage auf dem eigenen Server. Die Bibliothek durchsucht Text und Handschrift, ohne auf den exakten Wortlaut zu bestehen, und erkennt Schlagwörter.

Die App braucht keinen Server, alles bleibt auf dem Gerät. Ein selbst betriebener Server gleicht optional Geräte ab (`docs/adr/0017-lokal-zuerst.md`).

## Server installieren

Linux mit systemd oder Docker: **[docs/DEPLOY.md](docs/DEPLOY.md)**. Eingerichtet wird im Heimnetz, erreichbar unter `http://<lan-adresse>:8787`.

## Entwickeln

```sh
make test
make generate
make mac
make ipad
make server       # lokal auf 127.0.0.1:8787, Setup-Token im Log
make server-lan   # für ein echtes iPad im LAN
```

Das Xcode-Projekt kommt aus `project.yml`. Nicht die `xcodeproj` von Hand ändern.

`AGENTS.md` für die Arbeit am Repo. `docs/PRODUCT.md` für die Grenzen.
