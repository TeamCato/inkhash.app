# inkhash

> **In Entwicklung.** inkhash ist noch nicht fertig. Speicherformat, API und Oberfläche können sich ändern, und es gibt noch keine App im App Store. Abgeglichen wird über Kennel, den Server des Haushalts (siehe `docs/DEPLOY.md`).

Notizen für iPad, iPhone und Mac. Handschrift auf dem iPad, Text auf beiden, Abgleich über den eigenen Server. Die Bibliothek durchsucht Text und Handschrift, ohne auf den exakten Wortlaut zu bestehen, und erkennt Schlagwörter.

Die App braucht keinen Server, alles bleibt auf dem Gerät. Kennel, ein selbst betriebener Server, gleicht optional Geräte ab (`docs/adr/0017-lokal-zuerst.md`, `docs/adr/0067-abgleich-ueber-kennel.md`).

## Server

inkhash gleicht über das Modul `inkhash` von Kennel ab: **[docs/DEPLOY.md](docs/DEPLOY.md)**.

## Entwickeln

```sh
make test
make generate
make mac
make ipad
```

Das Xcode-Projekt kommt aus `project.yml`. Nicht die `xcodeproj` von Hand ändern.

`AGENTS.md` für die Arbeit am Repo. `docs/PRODUCT.md` für die Grenzen.
