# Inkhash — Anleitung für Agenten

Inkhash ist eine Notiz-App für iPad, iPhone und macOS. Sie funktioniert ganz lokal. Ein selbst betriebener Server gleicht optional ab, siehe ADR 0017.
Lies diese Datei, bevor du etwas änderst.

## Wahrheit, in dieser Reihenfolge

1. `docs/PRODUCT.md` — was die App ist und was sie nicht wird
2. `docs/DOMAIN.md` — die Wörter, die im Code so heißen müssen
3. `docs/adr/` — getroffene Entscheidungen. Nicht neu verhandeln, ohne eine neue ADR zu schreiben
4. `docs/API.md` — Vertrag zwischen App und Server
5. `docs/ARCHITECTURE.md` — wo Code wohnt und wer was besitzen darf
6. `docs/PITFALLS.md` — bekannte Fallen. Vor Änderungen an Sync, PencilKit, Markdown oder Suche lesen. Nach einem behobenen, wiederkehrenden Fehler einen Eintrag anhängen

Es gibt keinen Ordner `brain` und keine zweite Sourcemap. Was ein Agent wissen muss, steht in `docs/` oder im Code, den ein Test bewacht.

## Docs first

Eine Änderung am Verhalten, am Speicherformat, an der Suche oder am Sync beginnt im selben Schritt mit der passenden Doku:

- eine Entscheidung, die man später bereuen kann → neue ADR
- Vertragsänderung → `docs/API.md` und ein Test auf beiden Seiten
- wiederkehrende Falle → `docs/PITFALLS.md` plus ein Test, wenn sich die Falle prüfen lässt

Doku, die dem Code widerspricht, ist ein Fehler. Korrigiere sie im selben Schritt wie den Code.

## Grenzen

- Der Server speichert, liefert aus und synchronisiert. Er erkennt keine Handschrift, rendert nicht und leitet keine Tags ab.
- Suche läuft auf dem Gerät über die lokale Bibliothek, inklusive der mitgelieferten Abschriften.
- Nichts in der App darf einen Server voraussetzen. Ohne Anmeldung muss alles außer dem Abgleich gehen.
- Kein iCloud als Ablage oder Abgleich (iCloud Drive, CloudKit), kein zweites Sync-Ziel, kein Assistent und kein Embedding-Modell in der App. Das iCloud-Backup des Geräts ist erlaubt und erwünscht (ADR 0051).
- Keine Notion-Datenbanken, keine Whiteboards.
- Das iOS-Ziel läuft auf iPad und iPhone, das Layout folgt der Breite, nicht dem Gerät (ADR 0026). Auf dem Mac gibt es keine Zeichenfläche: macOS PencilKit kann `PKDrawing` lesen und zeichnen, aber kein `PKCanvasView`.
- Projektstruktur kommt aus `project.yml`. Die `xcodeproj` nicht von Hand editieren. Nach Änderungen an `project.yml`: `make generate`.

## Befehle

- `make test` — Swift-Paket, Server und der Vertragstest zwischen beiden (`make contract-test`)
- `make app-test` — App-Tests im iPad-Simulator (Editor, Bibliothek, Export)
- `make server` — API auf `127.0.0.1:8787`, Daten in `.data/`. Ohne Accounts steht der Setup-Token für `/admin` im Log
- `make server-lan` — bindet `0.0.0.0`
- `make server-test` — Testserver aus `.test-env/env`: eigener Port, alle Interfaces, eigene Daten. Die Datei ist lokal und nicht eingecheckt
- `make ipad-device TEAM=… DEVICE=…` — signiert aufs echte iPad oder iPhone. Braucht ein Apple-Konto in Xcode
- `make server-package VERSION=X.Y.Z` — Release-Paket des Servers nach `.build/release/`. Veröffentlicht wird per Tag `server-vX.Y.Z`, siehe `docs/RELEASE.md`
- `make generate` — Xcode-Projekt erzeugen
- `make mac` / `make ipad` / `make iphone` — bauen

## Sprache

Oberfläche Deutsch. Code, Typen und Commits Englisch.
