# Abgabe und Release

Für Maintainer und Agenten. Betreiber lesen `docs/DEPLOY.md`. Hintergrund: ADR 0039 (Server) und ADR 0064 (Abgabe).

## Abgabe auf `main`

Keine Pull Requests, nie direkt auf `main` pushen. Arbeit auf einem eigenen Branch, aufgesetzt auf dem aktuellen `origin/main`:

```sh
git fetch origin main
git switch -c feat/etwas origin/main
# … Änderungen, make test …
git push -u origin feat/etwas
```

Die Action `CI` läuft auf dem Runner auf Dominiks Mac: Fast-Forward-Prüfung, `make test`, `make app-test`, `make ui-test`, Builds für Mac, iPad und iPhone. Ist alles grün, setzt sie `main` per Fast-Forward auf den Commit. Installiert wird nicht vom Runner: Danach ruft der Agent auf dem Mac `tools/install-local.sh` auf. Ist der Branch hinter `main`, schlägt der Lauf fehl: `git rebase origin/main`, dann `git push --force-with-lease`.

Die Build-Nummer ist `git rev-list --count HEAD`. Die Marketing-Version bleibt, bis ein Release sie hebt.

### Runner auf dem Mac

Einmalig, im Konto von Dominik, nicht als root. Den Token (eine Stunde gültig) holt ein Admin mit `gh api -X POST repos/teamCato/inkhash.app/actions/runners/registration-token --jq .token`.

```sh
mkdir ~/actions-runner && cd ~/actions-runner
# actions-runner-osx-arm64-<version>.tar.gz von github.com/actions/runner/releases laden und entpacken
./config.sh --url https://github.com/teamCato/inkhash.app --token <TOKEN> --labels macOS --name inkhash-mac --unattended
./svc.sh install && ./svc.sh start
```

`svc.sh` legt einen LaunchAgent an; der Runner läuft nur, solange Dominik angemeldet ist. `./svc.sh status` zeigt, ob er läuft. Für Pull Requests von außen verlangt das Repository eine Freigabe, bevor Workflows laufen (ADR 0064).

Team und Ziele der Installation stehen in `~/.config/inkhash/install.env` (nicht eingecheckt):

```sh
TEAM=<team id>
DEVICES="<udid> <udid>"   # xcrun devicectl list devices
MAC_TARGETS="/Applications /Volumes/Dominik"
```

Danach legt das Skript Mac-App und iOS-Build im Depot ab (`../depot/scripts/publish.sh`, interne Download-Seite unter `/Volumes/Media/Apps`). Fehlt das Depot oder der Ordner, gibt es eine Warnung, die Installation läuft trotzdem durch. Ein anderes Skript setzt `DEPOT_PUBLISH`.

## Release der App

Nur wenn Dominik „Release“ sagt: `MARKETING_VERSION` in `project.yml` heben, Commit auf einem Branch wie oben.

Den Server veröffentlicht Kennel (ADR 0067).
