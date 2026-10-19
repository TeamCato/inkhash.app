# Inkhash — Anleitung für Agenten

Inkhash ist eine Notiz-App für iPad, iPhone und macOS. Sie funktioniert ganz lokal. Kennel, der selbst betriebene Server des Haushalts, gleicht optional ab, siehe ADR 0017 und 0067. Einen eigenen inkhash-Server gibt es nicht mehr; der Server-Teil ist Kennels Modul `inkhash` in dessen Repo.
Lies diese Datei, bevor du etwas änderst.

## Wahrheit, in dieser Reihenfolge

1. `docs/PRODUCT.md` — was die App ist und was sie nicht wird
2. `docs/DOMAIN.md` — die Wörter, die im Code so heißen müssen
3. `docs/adr/` — getroffene Entscheidungen. Nicht neu verhandeln, ohne eine neue ADR zu schreiben
4. `docs/API.md` — Vertrag zwischen App und Kennels Modul `inkhash`
5. `docs/ARCHITECTURE.md` — wo Code wohnt und wer was besitzen darf
6. `docs/PITFALLS.md` — bekannte Fallen. Vor Änderungen an Sync, PencilKit, Markdown oder Suche lesen. Nach einem behobenen, wiederkehrenden Fehler einen Eintrag anhängen

Es gibt keinen Ordner `brain` und keine zweite Sourcemap. Was ein Agent wissen muss, steht in `docs/` oder im Code, den ein Test bewacht.

## Docs first

Eine Änderung am Verhalten, am Speicherformat, an der Suche oder am Sync beginnt im selben Schritt mit der passenden Doku:

- eine Entscheidung, die man später bereuen kann → neue ADR
- Vertragsänderung → `docs/API.md` hier, `docs/modules/inkhash.md` und ein Test in Kennel, `ContractTests` hier
- wiederkehrende Falle → `docs/PITFALLS.md` plus ein Test, wenn sich die Falle prüfen lässt

Doku, die dem Code widerspricht, ist ein Fehler. Korrigiere sie im selben Schritt wie den Code.

## Grenzen

- Der Server speichert, liefert aus und synchronisiert. Er erkennt keine Handschrift, rendert nicht und leitet keine Tags ab.
- Suche läuft auf dem Gerät über die lokale Bibliothek, inklusive der mitgelieferten Abschriften.
- Nichts in der App darf einen Server voraussetzen. Ohne Anmeldung muss alles außer dem Abgleich gehen.
- Kein iCloud als Ablage oder Abgleich (iCloud Drive, CloudKit), kein zweites Sync-Ziel, kein Assistent und kein Embedding-Modell in der App. Das iCloud-Backup des Geräts ist erlaubt und erwünscht (ADR 0051).
- Keine Notion-Datenbanken, keine Whiteboards.
- Das iOS-Ziel läuft auf iPad und iPhone, das Layout folgt der Breite, nicht dem Gerät (ADR 0026). Auf dem Mac gibt es kein `PKCanvasView`: macOS PencilKit kann `PKDrawing` lesen, rendern und Striche bauen. Der Mac zeichnet mit der Maus über eine eigene Fläche (ADR 0058), ohne Elemente zu bearbeiten.
- Projektstruktur kommt aus `project.yml`. Die `xcodeproj` nicht von Hand editieren. Nach Änderungen an `project.yml`: `make generate`.

## Abgabe

Keine Pull Requests, nie direkt auf `main` pushen. Eigener Branch auf `origin/main`, `make test`, dann `git push -u origin <branch>`. Die CI auf Dominiks Mac testet und spult `main` vor. Ist `main` grün, installiert der Agent auf dem Mac die Apps mit `tools/install-local.sh` (ADR 0064, `docs/RELEASE.md`). Versionen ändern sich nur bei einem Release.

## Befehle

- `make test` — Swift-Paket und der Vertragstest gegen Kennel (`make contract-test`, braucht einen Kennel-Checkout in `KENNEL_DIR` oder `../kennel`, sonst übersprungen)
- `make app-test` — App-Tests im iPad-Simulator (Editor, Bibliothek, Export)
- `make ui-test` — Tresor-Sheets im iPhone-Simulator gegen Kennels Testserver (braucht Kennel wie `make contract-test`)
- `make mac-test` — Mac-Editor und Notizblatt ohne App-Host, mit eigener Wegwerf-Bibliothek. Schreibt Bilder nach `/tmp/inkhash-*.png` zum Ansehen
- `make ipad-device TEAM=… DEVICE=…` — signiert aufs echte iPad oder iPhone. Braucht ein Apple-Konto in Xcode
- `make generate` — Xcode-Projekt erzeugen
- `make mac` / `make ipad` / `make iphone` — bauen

## Sprache

Oberfläche Deutsch. Code, Typen und Commits Englisch.
