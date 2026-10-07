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
| transcript | Von der Texterkennung gelesene Handschrift. Pro Seite und als Zusammenfassung auf der Notiz. |
| tag | Schlagwort ohne `#`, kleingeschrieben, erste Fundstelle gewinnt. |
| title | Titel der Notiz. Automatisch aus dem Inhalt, bis man ihn setzt (ADR 0019). |
| displayTitle | Titel für die Liste. Bei leerem Handschrift-Titel die erste Zeile der Abschrift. |
| baseRevision | Die Revision, die das Gerät beim Schreiben noch für aktuell hielt. |
| dirty | Lokal geändert, noch nicht sauber bestätigt. |
| conflict | Server und Gerät haben beide geschrieben. Beide Fassungen bleiben liegen. |
| Bibliothek | Alle Notizen eines Workspace auf einem Gerät. Gehört keinem Account, gleicht höchstens mit einem Server-Workspace ab. |
| Workspace | Eigene Bibliothek mit eigenen Ordnern, Schlagwörtern und Suche, z. B. Privat und Arbeit. Lokal oder mit einem Server-Workspace verbunden (ADR 0020). Name, Symbol und eigenes Bild (`icon`) sind sein Aussehen; Aussehen und Reihenfolge gleicht der Server ab, wenn der Workspace verbunden ist (ADR 0043). |
| Aussehen | Name, Symbol und Bild eines Workspace (`WorkspaceLook`). Die letzte Änderung gewinnt (ADR 0043). |
| Server | Adresse plus angemeldeter Account (`ServerEntry`). Ein Gerät kennt mehrere. |
| main | Der Workspace, den jeder Account auf dem Server hat. Auch ohne Präfix erreichbar. |
| folder | Pfad an der Notiz, Segmente mit `/`. Leer heißt Wurzel des Workspace. In der Oberfläche „Pfad“, geschrieben mit ` / ` (ADR 0022). |
| Baum | Die Seitenleiste: Ordner aus den Pfaden, Notizen als Blätter. Zugeklappte Knoten nur auf dem Gerät (`sidebar.json`, ADR 0022). |
| favorite | Favorit, an der Notiz, wird abgeglichen. |
| Papierkorb | Notizen mit `deletedAt`. Wiederherstellbar. |
| Account | Name und Passwort an einem Server. Sieht nur die eigenen Notizen. |
| gebunden | Account und Server-Workspace, mit denen die Bibliothek zuletzt abgeglichen hat. Ein Wechsel setzt alle Revisionen auf 0. |
| Sitzung | Zufalls-Token nach dem Anmelden. Liegt in der Keychain, nicht das Setup-Token. |
| Setup-Token | Zufallswert, den der Server ohne Accounts beim Start ins Log schreibt. Legt nur den Admin an, dann ungültig. |
| Admin | Der erste Account. Legt auf `/admin` weitere Accounts an, sonst ein Account wie jeder andere (ADR 0021). |

`# Titel` ist eine Überschrift. `#titel` ist ein Tag. In Handschrift-Abschriften ist `# titel` ebenfalls ein Tag.
