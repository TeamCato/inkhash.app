# API

Basis: `http://host:8787`. `GET /v1/health`, das Einrichten, das Anmelden und die Seite `/admin` sind offen. Alles andere verlangt `Authorization: Bearer <sitzung>`.

Solange es keinen Account gibt, erzeugt der Server beim Start einen zufälligen Setup-Token und schreibt ihn in sein Log. Er ist kein Login und legt nur den ersten Account an, den Admin (`POST /v1/setup`). Danach gilt er nicht mehr. Weitere Accounts legt nur der Admin an (`POST /v1/accounts`), mit Name und Startpasswort. Es gibt keine E-Mail und keine Selbstregistrierung. Siehe ADR 0021.

Ein Account sieht nur seine eigenen Notizen. Passwörter liegen als PBKDF2-HMAC-SHA256 mit 600.000 Runden. Ältere Hashes mit weniger Runden ersetzt der nächste erfolgreiche Login. Die Sitzung ist ein Zufallswert, gespeichert nur als SHA-256. Sie endet nach 90 Tagen ohne Benutzung, danach 401. Acht Fehlversuche sperren den Namen für 15 Minuten. 30 Fehlversuche von derselben Adresse (Passwort, Setup-Token) sperren Anmelden und Einrichten für 15 Minuten; bei IPv6 zählt das /64-Netz. Laufen schon zu viele Passwortprüfungen, antwortet `POST /v1/session` sofort 429 `slow-down`. Siehe ADR 0016 und 0038.

JSON-Bodies kommen mit `Content-Type: application/json`, sonst 415 `unsupported-media-type`. `POST /v1/setup` und `POST /v1/session` nehmen höchstens 16 KiB.

## Endpunkte

| Methode | Pfad | Bedeutung |
| --- | --- | --- |
| GET | `/v1/health` | `{ "ok": true, "registration": "setup" \| "closed" }`, ohne Sitzung |
| POST | `/v1/setup` | `{ "setupToken", "name", "password" }` → 201 `{ "token", "account": { "id", "name", "admin": true } }`, ohne Sitzung |
| POST | `/v1/session` | `{ "name", "password" }` → `{ "token", "account": { "id", "name", "admin" } }` |
| DELETE | `/v1/session` | Sitzung beenden |
| GET | `/v1/accounts` | nur Admin: `{ "accounts": [{ "id", "name", "admin", "createdAt" }] }`, nach Name |
| POST | `/v1/accounts` | nur Admin: `{ "name", "password" }` → 201 `{ "id", "name", "admin": false, "createdAt" }`. Keine Sitzung für den neuen Account |
| GET | `/admin` | Verwaltungsseite, HTML. Skript unter `/admin/client.js` |
| GET | `/v1/workspaces` | `{ "workspaces": [Workspace], "ordered" }` in der Reihenfolge des Accounts |
| POST | `/v1/workspaces` | `{ "name" }` → 201 Workspace. Name 1–40 Zeichen, höchstens 50 Workspaces einschließlich `main` |
| PATCH | `/v1/workspaces/{id}` | `{ "name"?, "symbol"?, "icon"? }` → Workspace |
| PUT | `/v1/workspace-order` | `{ "ids": [...] }` → wie `GET /v1/workspaces` |
| GET | `/v1/changes?after=<cursor>&limit=<n>` | `{ "cursor", "hasMore", "changes": [{ "cursor", "noteId", "revision", "deleted" }] }` |
| GET | `/v1/notes/{id}` | die Notiz, auch wenn sie gelöscht ist |
| PUT | `/v1/notes/{id}` | Body `{ "baseRevision", "note" }`. 201 beim Anlegen, 200 beim Aktualisieren, 409 bei Konflikt, 404 bei unbekannter Notiz mit `baseRevision` > 0 |
| DELETE | `/v1/notes/{id}?baseRevision=<n>` | Grabstein. Der Inhalt bleibt erhalten |
| PUT | `/v1/blobs/{sha256}` | Rohbytes. 400, wenn der Hash nicht passt. 204, wenn er liegt |
| GET | `/v1/blobs/{sha256}` | Rohbytes |

Ein Workspace ist `{ "id", "name", "symbol", "icon", "updatedAt" }`. `symbol` ist der Name eines SF Symbols (`[a-z0-9]` in Teilen mit `.`, höchstens 64 Zeichen), `icon` der sha256 eines Blobs im selben Workspace, `updatedAt` die letzte Änderung über `PATCH`. Alle drei sind `null`, solange kein Gerät das Aussehen gesetzt hat. `PATCH` ändert nur die genannten Felder, mindestens eines; `"icon": null` entfernt das Bild. Ein `icon`, das nicht als Blob im Workspace liegt, ist 400 mit `reason: "icon"`, ein ungültiges Symbol 400 mit `reason: "symbol"`. Siehe ADR 0043.

`ordered` ist falsch, solange der Account keine Reihenfolge gespeichert hat; dann kommt `main` zuerst, die übrigen in der Reihenfolge des Anlegens. `PUT /v1/workspace-order` ordnet die genannten Workspaces unter den Plätzen, die sie schon haben; nicht genannte bleiben stehen. Ein neuer Workspace kommt ans Ende. Unbekannte oder doppelte IDs sind 400 mit `reason: "order"`.

Die Routen für Änderungen, Notizen und Blobs gelten für den Workspace `main`. Dieselben Routen unter `/v1/workspaces/{ws}/` gelten für den Workspace `ws`, jeder mit eigenem Cursor. Ein unbekannter Workspace ist 404. Server ohne Workspaces antworten auf `GET /v1/workspaces` mit 404; die App kennt dort nur `main`. Siehe ADR 0020.

409 liefert `{ "error": "conflict", "note": { ...aktuelle Fassung } }`.

`baseRevision` 0 legt an. Ist die ID schon da, ist auch das ein Konflikt.

`baseRevision` > 0 auf eine Notiz, die der Server nicht kennt, ist 404 `not-found`, zum Beispiel nach einem Restore aus einer älteren Sicherung. Der Client legt die Notiz dann mit `baseRevision` 0 neu an. Ein `DELETE` darauf ist ebenfalls 404; die Notiz bleibt dann nur im lokalen Papierkorb, mit Revision 0.

Passt `baseRevision` nicht, ist der Inhalt aber genau der gespeicherte (`kind`, `title`, `markdown`, `transcript`, `tags`, `pages`, `folder`, `favorite`, `paper`), antwortet der Server mit 200 und der gespeicherten Fassung, ohne neue Revision. Das ist der Retry nach einer verlorenen Antwort. Für gelöschte Notizen gilt das nicht.

Ein `PUT` mit passender `baseRevision` auf eine gelöschte Notiz holt sie zurück: `deletedAt` ist danach wieder `null`.

`title` setzt der Client: automatisch aus dem Inhalt oder von Hand, siehe ADR 0019. Der Server prüft nur die Länge.

Der Server setzt `updatedAt` und `revision` selbst. Mitgeschickte Werte dafür werden ignoriert. Notiz-IDs sind kleingeschriebene UUIDs. Account-IDs ebenfalls. Blob-Namen sind 64 hexadezimale Zeichen, kleingeschrieben.

`POST /v1/setup` antwortet mit 401 bei falschem Setup-Token, 403 `setup-done`, wenn es schon einen Account gibt, und 429 `slow-down` nach zu vielen Fehlversuchen. `GET` und `POST /v1/accounts` antworten ohne Sitzung mit 401, mit der Sitzung eines anderen Accounts mit 403 `forbidden`. 409 `name-taken`, wenn der Name schon da ist. Der Name ist 2–32 Zeichen, klein, aus Buchstaben, Ziffern, `.`, `_`, `-`, und beginnt und endet mit Buchstabe oder Ziffer. Das Passwort hat 8–200 Zeichen. `403 setup-done` kommt vor jeder Prüfung des Bodys.

## Notiz

```json
{
  "schemaVersion": 1,
  "id": "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10",
  "kind": "text",
  "title": "Inkhash",
  "revision": 1,
  "updatedAt": "2026-09-30T06:00:00Z",
  "deletedAt": null,
  "markdown": "# Inkhash\n",
  "transcript": null,
  "tags": ["eigen"],
  "pages": null,
  "folder": "Projekte/Inkhash",
  "favorite": false,
  "paper": { "color": "#FAF5E8", "pattern": "blank" }
}
```

`folder` ist ein Pfad aus Segmenten mit `/`, jedes 1–60 Zeichen ohne Rand-Leerzeichen, insgesamt höchstens 200; leer heißt kein Ordner. `favorite` ist ein Boolean. Fehlen beide, gelten `""` und `false`. Gespeicherte Notizen von vorher werden so ausgeliefert. Beide zählen zum Inhalt für den Retry-Vergleich.

`paper` ist optional und gilt für die ganze Notiz (ADR 0042): `color` als `#RRGGBB` (der Server speichert groß) und `pattern` aus `blank`, `grid`, `lines`, `dots`; fehlt `pattern`, gilt `blank`. Eine Textnotiz hat nur `blank`. Fehlt `paper` oder ist es `null`, gilt das Standardpapier, und der Server lässt den Schlüssel weg. Der Server prüft nur die Form, nicht die Palette der App. Ein ungültiges Papier ergibt 400 `bad-request` mit `reason: "paper"`. `paper` zählt zum Inhalt für den Retry-Vergleich.

`kind: "ink"` hat `markdown: null`, `transcript` als String und `pages` als Liste. Eine Seite:

```json
{
  "id": "11111111-2222-4333-8444-555555555555",
  "blob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "width": 768,
  "height": 1024,
  "transcript": "Reise #alpen",
  "tags": ["alpen"],
  "elements": [
    {
      "id": "2222aaaa-1111-4222-8333-444455556666",
      "kind": "image",
      "x": 384, "y": 300, "width": 400, "height": 300, "rotation": 0.05, "z": 0,
      "blob": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "frame": { "style": "polaroid", "color": "#FFFFFF", "width": 12, "shadow": true },
      "mask": { "kind": "freehand", "points": [{ "x": 0, "y": 0 }, { "x": 1, "y": 0.1 }, { "x": 0.5, "y": 1 }] }
    },
    {
      "id": "5555dddd-1111-4222-8333-444455556666",
      "kind": "link",
      "x": 200, "y": 700, "width": 240, "height": 80, "rotation": 0, "z": 1,
      "link": "inkhash://note/6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10"
    }
  ]
}
```

`elements` liegt unter der Tinte, siehe ADR 0028. Höchstens 500 je Seite. Fehlt die Liste, gilt `[]`; der Server liefert sie immer, auch für Seiten, die vorher gespeichert wurden. `elements` zählt zum Inhalt für den Retry-Vergleich.

Jedes Element hat `id` (UUID, wird kleingeschrieben), `kind` (`image`, `shape`, `tape`, `link`, `excerpt`), Mittelpunkt `x`/`y` in Seitenkoordinaten (−20000…40000), `width`/`height` (über 0, höchstens 20000), `rotation` in Bogenmaß und `z` als ganze Zahl. Dazu je nach Art:

- `image`: `blob` ist Pflicht (wie Zeichnungs-Blobs). Optional `frame` mit `style` (`none`, `solid`, `polaroid`), `color`, `width` 0…100 und `shadow`, alle vier Pflicht. Optional `mask` mit `kind` (`circle`, `rectangle`, `freehand`) und `points` (`x`/`y` 0…1, höchstens 500); `freehand` braucht mindestens 3 Punkte, `circle` und `rectangle` keine.
- `shape`: `shape` (`line`, `rect`, `ellipse`, `triangle`) ist Pflicht. Optional `stroke`, `strokeWidth` 0…100, `fill`, `fillOpacity` 0…1.
- `tape`: optional `color`.
- `link`: `link` ist Pflicht.
- `excerpt`: `link` ist Pflicht und ein Ausschnitt-Ziel (ADR 0037): `inkhash://note/<id>/page/<pageID>?rect=x,y,w,h` oder `inkhash://note/<id>?text`, optional gefolgt von `&name=wert` mit prozentkodierten Werten (`section`, `from`, `to`). IDs kleingeschrieben. Der Server prüft nur diese Form und sieht nicht in die Notiz.

Jedes Element darf `link` tragen: höchstens 2000 Zeichen, beginnend mit `https://`, `http://`, `mailto:` oder `inkhash://note/`. Farben sind `#RRGGBB`, Groß- und Kleinschreibung egal; der Server speichert sie groß. Felder, die nicht zur Art gehören, sind ein Fehler. `null` heißt dasselbe wie ein fehlendes Feld; der Server lässt beides weg und schreibt die Schlüssel in fester Reihenfolge. Ein ungültiges Element ergibt 400 `bad-request` mit `reason: "element"`.

Tags enthalten kein `#`, kein Leerzeichen, höchstens 40 Zeichen. Der Server prüft die Form und leitet sie nicht aus dem Text ab.

Markdown, das der Client schreibt, ist die kanonische Teilmenge aus `MarkdownCodec`: Überschriften mit Leerzeichen nach den Rauten, Listen, Aufgaben, Code-Zäune, Tabellen (ADR 0027) mit Ausrichtung in der Trennzeile und einer Kommentarzeile `<!-- inkhash:table … -->` direkt danach (ADR 0036), `**`, `*`, `` ` `` Links `[Text](Ziel)` (ADR 0024, 0031) und Ausschnitte `![Label](Ausschnitt-Ziel)` als eigener Absatz, auf eine Seite oder auf Text (ADR 0032, 0037). Der Server prüft Ausschnitte nicht. `#wort` bleibt im Absatz stehen und ist ein Tag.

### Grenzen

Längen zählt der Server in UTF-16-Einheiten (JavaScript `length`); ein Emoji kann bis zu elf davon belegen. Die App misst genauso (`Limits`, `clippedUTF16` im Kern). Was darüber liegt, ist 400 `bad-request` mit `reason`:

| Feld | Grenze | `reason` |
| --- | --- | --- |
| `title` | höchstens 200 | `title` |
| `tags` der Notiz, `tags` einer Seite | höchstens 50, je 1–40 | `tags`, `page tags` |
| `markdown` | höchstens 1 000 000 | `markdown` |
| `transcript` der Notiz, einer Seite | höchstens 100 000 | `transcript`, `page transcript` |
| `pages` | höchstens 100 | `pages` |
| `width`, `height` einer Seite | 1–10 000 | `page size` |
| `elements` einer Seite | höchstens 500 | `element` |
| `folder` | höchstens 200, Segmente 1–60 | `folder` |

Ein JSON-Body darf 2 MiB haben (ohne Sitzung 16 KiB), ein Blob 20 MiB; darüber antwortet der Server 413 `too-large`. Die App kappt Schlagwörter bei 50 (die ersten gewinnen), teilt einen PDF-Import ab 100 Seiten auf mehrere Notizen und kürzt sehr hohe Seiten auf 10 000. Lehnt der Server eine Notiz trotzdem mit 400 oder 413 ab, bleibt sie auf dem Gerät ungesendet, der Abgleich der übrigen läuft weiter, und der Status nennt sie.

## Änderungen

`/v1/changes` liefert pro Notiz nur den letzten Eintrag, aufsteigend nach `cursor`. `limit` ist 1–1000, ohne Angabe 500. Bei `hasMore: true` ist `cursor` der letzte gelieferte Eintrag, und der Client fragt mit diesem Cursor weiter. Sonst ist `cursor` der aktuelle Stand des Servers. Server ohne Seiten lassen `hasMore` weg, der Client liest das als `false`.

Ein `after` jenseits des aktuellen Standes, etwa nach einem Restore, zählt als 0: der Server liefert alle Notizen, und das Gerät prüft jede einmal. Siehe ADR 0015.

## Reihenfolge

Blobs hochladen, bevor die Notiz sie nennt: Zeichnungen der Seiten und Bilder der Elemente. Der Server erzwingt das nicht. Ein Gerät, das die Notiz zuerst sieht, lädt fehlende Blobs nach und bricht den Abgleich ab, wenn ein Blob fehlt, statt den Cursor darüber hinwegzuschieben.

Es gibt keinen Such-Endpunkt. Jedes Gerät sucht in seiner Kopie.
