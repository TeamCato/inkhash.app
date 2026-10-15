# 0064 Abgabe ohne Pull Request

Status: angenommen

## Entscheidung

Agenten und Maintainer schieben ihre Arbeit auf einen eigenen Branch, nie direkt auf `main` und ohne Pull Request. Die Action `CI` (`.github/workflows/ci.yml`) läuft auf einem selbst betriebenen Runner auf Dominiks Mac (Labels `self-hosted`, `macOS`):

1. Prüfen, dass der Branch `main` vorspult. Liegt er hinter `main`, schlägt der Lauf fehl; der Branch wird auf `origin/main` umgebaut und neu geschoben.
2. `make test` (Swift-Paket, Server, Vertragstest), `make app-test`, dann `make mac`, `make ipad` und `make iphone`.
3. Alles grün: `main` wird per Fast-Forward auf den Commit gesetzt. Kein Merge-Commit von CI, kein Squash.
4. Danach baut `tools/install-local.sh` die Apps signiert mit Dominiks Team und installiert sie nach `/Applications`, nach `/Volumes/Dominik` und auf die eingetragenen Geräte. Ein gesperrtes oder nicht erreichbares Gerät ist eine Warnung, kein Fehler: `main` steht dann schon.

Die Build-Nummer ist die Zahl der Commits auf dem gebauten Stand (`git rev-list --count HEAD`). Die Marketing-Version in `project.yml` und Tags `server-vX.Y.Z` ändern sich nur, wenn Dominik „Release“ sagt (`docs/RELEASE.md`).

Der Server-Workflow `server.yml` läuft weiter auf `ubuntu-latest`, weil er den Container für Linux baut. Der Weg der Server-Releases (GitHub Releases und öffentliches Image auf GHCR) bleibt, wie ADR 0039 ihn beschreibt.

## Warum

Die Arbeit kommt fast ganz von Agenten, die Prüfung macht der Rechner. Ein Pull Request fügt nur einen Klick hinzu, den niemand mit mehr Wissen als die Tests drückt. Die App-Tests und Builds für iPad, iPhone und Mac brauchen Xcode und Simulatoren; auf gehosteten macOS-Runnern ist das langsam, und die signierte Installation geht ohnehin nur auf dem Mac mit dem Apple-Konto.

Fast-Forward statt Merge hält `main` linear: Was auf `main` steht, ist genau der Commit, den der Runner getestet hat.

## Risiko des Runners

Das Repository bleibt öffentlich, damit Release-Pakete und Compose-Dateien ohne Anmeldung zu laden sind. Ein Runner an einem öffentlichen Repository führt Code auf Dominiks Mac aus, mit seinem Schlüsselbund, seinem SSH-Schlüssel und seinen Geräten. Ein Pull Request aus einem Fork könnte einen eigenen Workflow mit `runs-on: self-hosted` mitbringen. Deshalb:

- `ci.yml` reagiert nur auf Pushes auf Branches außer `main` und auf `workflow_dispatch`, nie auf `pull_request` oder `pull_request_target`. Pushen kann nur, wer Schreibrechte hat.
- Der erste Job läuft nur, wenn `github.repository_owner == 'teamCato'` und `github.actor == 'nikdom'`. Agenten pushen mit Dominiks Schlüssel, erscheinen also als `nikdom`.
- In den Repository-Einstellungen brauchen Workflows aus Pull Requests von außen eine Freigabe („Require approval for all outside collaborators“). Das fängt fremde Workflows ab, die selbst `self-hosted` anfordern.
- Der Runner läuft als LaunchAgent in Dominiks Sitzung, nicht als root.

## Folgen

- Der Schub auf `main` geht über den SSH-Schlüssel des Mac-Nutzers, nicht über `GITHUB_TOKEN`: Der Token darf keine Workflow-Dateien ändern, und Pushes mit ihm lösen keine weiteren Workflows (etwa `server.yml`) aus.
- Ohne angemeldeten Dominik läuft keine CI; Pushes warten in der Warteschlange.
- Ein Branch, den `main` überholt hat, wird nie automatisch umgebaut.

## Nicht

Keine Pull Requests, kein Merge-Commit durch CI, kein Squash. Kein automatischer Versionssprung. Kein zweiter Runner für die App.
