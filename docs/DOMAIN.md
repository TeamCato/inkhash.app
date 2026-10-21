# Domäne

Diese Wörter heißen im Code so.

| Wort | Bedeutung |
| --- | --- |
| Note | Eine Notiz. Genau eine Art: `text` oder `ink`. |
| revision | Ganzzahl. Der Server vergibt sie. `0` heißt: noch nie zu diesem Account hochgeladen. |
| markdown | Kanonischer Text einer Textnotiz. Nicht die Darstellung. |
| page | Eine Handschriftseite. Breite, Höhe, Blob-Hash, Abschrift, Schlagwörter. |
| blob | Rohbytes einer `PKDrawing` oder eines Fotos (JPEG), adressiert mit SHA-256, kleingeschrieben. |
| element | Etwas auf einer Handschriftseite außer Tinte: `image`, `shape`, `tape`, `link` (Linkfläche) oder `excerpt` (Text-Ausschnitt, ADR 0035). Mittelpunkt, Größe, Drehung, Ebene `z`, Seitenkoordinaten (ADR 0028). |
| Link | Ziel an Text oder Element: Webadresse (`https://`, `http://`), E-Mail (`mailto:`) oder `inkhash://note/<id>` für eine andere Notiz. Getippte Ziele normalisiert `LinkTarget` (ADR 0027, 0031). |
| excerpt | Ausschnitt: ein Fenster auf ein Rechteck einer Handschriftseite oder auf Absätze einer Textnotiz. Im Text ein Absatz `![Label](Ziel)`, auf der Seite ein Element mit dem Ziel in `link`. Nur Verweis, keine Kopie (ADR 0032, 0037). |
| ExcerptTarget | Ziel eines Ausschnitts: `…/page/<pageID>?rect=…` (Seite) oder `…?text[&section=…][&from=…&to=…]` (Text). |
| section | Abschnitt einer Textnotiz: von einer Überschrift bis zur nächsten gleicher oder höherer Ebene (ADR 0035, 0037). |
| TableFormat | Ausrichtung, Breiten, Kopfzeile und Zebra einer Tabelle, an ihrer ersten Zeile (ADR 0036). |
| tableRow | Eine Zeile einer Markdown-Tabelle im Editor; Zellen durch Tabulator getrennt, die erste Zeile ist der Kopf. |
| Aufgabe | Etwas zu tun, das man abhaken kann (`TaskItem`). Im Text ein Kästchen `- [ ]`/`- [x]` (ADR 0027), in der Handschrift ein gemaltes Kästchen vor einer Zeile (`InkTask` in `tasks` der Seite, ADR 0060). |
| Fälligkeit | Tag, an dem eine Aufgabe fällig ist (`due`, `JJJJ-MM-TT`). Im Text `📅 JJJJ-MM-TT` am Zeilenende (`TaskDue`). Keine Uhrzeit. |
| Aufgabenliste | Alle Aufgaben eines Workspace auf einem Blatt, gelesen aus den Notizen, nicht gespeichert (`TaskList`, ADR 0060). |
| transcript | Von der Texterkennung gelesene Handschrift. Pro Seite und als Zusammenfassung auf der Notiz. |
| tag | Schlagwort ohne `#`, kleingeschrieben, erste Fundstelle gewinnt. |
| title | Titel der Notiz. Automatisch aus dem Inhalt, bis man ihn setzt (ADR 0019). |
| displayTitle | Titel für die Liste. Bei leerem Handschrift-Titel die erste Zeile der Abschrift. |
| baseRevision | Die Revision, die das Gerät beim Schreiben noch für aktuell hielt. |
| dirty | Lokal geändert, noch nicht sauber bestätigt. |
| conflict | Server und Gerät haben beide geschrieben. Beide Fassungen bleiben liegen, bis man sie vergleicht und eine, die andere oder beide behält (`NoteConflict`, ADR 0049). |
| Bibliothek | Alle Notizen eines Workspace auf einem Gerät. Gehört keinem Account, gleicht höchstens mit einem Server-Workspace ab. |
| Workspace | Eigene Bibliothek mit eigenen Ordnern, Schlagwörtern und Suche, z. B. Privat und Arbeit. „Nur hier“ oder „Abgeglichen“ mit einem Workspace in Kennel (ADR 0020, 0077). Name, Symbol und eigenes Bild (`icon`) sind sein Aussehen; Aussehen und Reihenfolge gleicht der Server ab, wenn der Workspace verbunden ist (ADR 0043). |
| Aussehen | Name, Symbol und Bild eines Workspace (`WorkspaceLook`). Die letzte Änderung gewinnt (ADR 0043). |
| Kennel | Adresse plus angemeldeter Account (`ServerEntry`, `WorkspaceRegistry.kennel`). Ein Gerät kennt höchstens einen (ADR 0077). In der Oberfläche nie „Server“. |
| Ort | Wo ein Workspace liegt: „Nur hier“, „Abgeglichen“ oder „Zieht um“ (`KennelPlace`, teamCato ADR 0009). Geändert nur im Abschnitt „Ort“. |
| Übernehmen | Dritter Schritt von „Mit Kennel verbinden“: was von diesem Gerät nach Kennel soll und was aus Kennel hierher kommt, mit Vorschlag je Zeile (`TakeOverPlanner`, ADR 0077). |
| Umwandeln | Ein verschlüsselter Workspace in Kennel wird zu einem unverschlüsselten auf demselben Speicher; der alte geht erst danach (`ConversionPlanner`, `Workspace.retiring`, ADR 0077). |
| Nachfolger | Der unverschlüsselte Workspace, in den ein verschlüsselter umgewandelt wurde. Andere Geräte erkennen ihn an Name und geteilten Notiz-IDs. |
| main | Der Workspace, den jeder Account auf dem Server hat. Auch ohne Präfix erreichbar. |
| folder | Pfad an der Notiz, Segmente mit `/`. Leer heißt Wurzel des Workspace. In der Oberfläche „Pfad“, geschrieben mit ` / ` (ADR 0022). |
| Baum | Die Seitenleiste: Ordner aus den Pfaden, Notizen als Blätter. Zugeklappte Knoten nur auf dem Gerät (`sidebar.json`, ADR 0022). |
| favorite | Favorit, an der Notiz, wird abgeglichen. |
| createdAt | Erstellungsdatum an der Notiz, setzt der Client, von Hand änderbar, wird abgeglichen. Fehlt es, gilt `updatedAt` (ADR 0048). In der Oberfläche „Erstellt“. |
| Papierkorb | Notizen mit `deletedAt`. Wiederherstellbar. |
| Account | Name und Passwort an einem Server. Sieht nur die eigenen Notizen. |
| gebunden | Account und Server-Workspace, mit denen die Bibliothek zuletzt abgeglichen hat. Ein Wechsel setzt alle Revisionen auf 0. |
| Sitzung | Zufalls-Token nach dem Anmelden. Liegt in der Keychain, nicht das Setup-Token. |
| Setup-Token | Zufallswert, den der Server ohne Accounts beim Start ins Log schreibt. Legt nur den Admin an, dann ungültig. |
| Admin | Darf auf `/admin` Accounts anlegen, umbenennen, Passwörter setzen, zu Admins machen und löschen, sonst ein Account wie jeder andere. Der erste Account ist Admin, der letzte bleibt es (ADR 0021, 0046). |
| Export | Eine Notiz als Datei (Markdown oder PDF) oder ein Workspace als ZIP mit lesbaren Dateien und einer Kopie für die App (ADR 0051). |
| Sicherung | Ein Workspace-Export, den der Import wieder als neue Notizen holt. Daneben das Geräte-Backup (iCloud-Backup, Time Machine), kein Sync-Ziel. |
| Tresor | Der Schlüssel eines Accounts auf dem Server, verpackt mit dem Wiederherstellungsschlüssel (`VaultRecord`, `/v1/vault`). Die App legt keinen mehr an; ein vorhandener wird nur noch zum Umwandeln geöffnet (ADR 0052, 0077). |
| Wiederherstellungsschlüssel | Öffnet den Tresor, wenn kein Gerät mit offenem Tresor da ist. Die App erzeugt ihn, 25 Zeichen in fünf Gruppen (`RecoveryKey`). Nur die Geräte kennen ihn, nicht der Server, nicht der Admin. Nicht das Login-Passwort (ADR 0054). |
| Kopplung | Übergabe des Account-Schlüssels an ein neues Gerät per QR-Code (`Pairing`, `/v1/vault/pairings`, ADR 0054). Nicht mehr in der Oberfläche (ADR 0077). |
| Beitrittscode | Einmal-Code aus Kennels Verwaltung, zwölf Zeichen, angezeigt `XXXX-XXXX-XXXX` (`JoinCode`). „Gerät hinzufügen“ meldet ohne Passwort am selben Account an, eine „Einladung“ legt einen neuen Account an (`POST /v1/join`, ADR 0071). |
| Beitrittslink | `<server>/join#<code>`, auch als QR-Code in Kennels Verwaltung. Belegt Adresse und Code vor (`JoinLink` aus KennelKit, ADR 0073). |
| App-Link | `inkhash://kennel/join?server=…&code=…`, öffnet „Mit Kennel verbinden“ vorbelegt (ADR 0071, 0077). |
| Im Netz gefunden | Kennel, die sich per Bonjour (`_kennel._tcp`) im Heimnetz ankündigen; ein Vorschlag fürs Adressfeld (`KennelConnectSection` aus KennelKitUI, ADR 0072, 0074). |
| sealed | Eine Notiz oder ein Blob, verschlüsselt mit dem Schlüssel des Accounts (`Sealer`). `schemaVersion: 2` auf dem Draht. |
| epoch | Zahl der Resets eines Tresors. Ändert die Bindung der Bibliotheken (`Workspaces.bindingKey`). |
| Unverschlüsselter Workspace | Ein Workspace in Kennel, dessen Notizen als Klartext gehen und lesbar im Speicher liegen (`WorkspaceLink.sealed == false`). Jeder neue ist es (ADR 0075, 0077). |
| Speicher eines Workspace | Der Speicher in Kennel, in dem die Notizen eines Server-Workspace liegen: der des Accounts oder ein eigener, den inkhash nutzen darf (ADR 0075). |

`# Titel` ist eine Überschrift. `#titel` ist ein Tag. In Handschrift-Abschriften ist `# titel` ebenfalls ein Tag.
