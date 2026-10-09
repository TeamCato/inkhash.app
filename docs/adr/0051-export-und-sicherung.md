# 0051 Export und Sicherung

Status: angenommen

## Entscheidung

Notizen verlassen die App als Dateien, auf drei Wegen:

- **Eine Notiz teilen oder exportieren.** Im Kontextmenü einer Notiz: „Teilen…“ öffnet das Teilen-Menü des Systems, „Als PDF/Markdown exportieren…“ legt eine Datei ab. Text wird Markdown (`.md`, der kanonische Text, ADR 0004). Handschrift wird PDF: je Seite eine PDF-Seite in Seitengröße, Papier und Elemente als Vektoren, die Tinte als Bild in Bändern von 1024 Punkten (`NotePDF`).
- **Einen Workspace exportieren.** Im Workspace unter „Sicherung“. Das ergibt eine ZIP-Datei mit `inkhash-export.json`, allen Notizen außerhalb des Papierkorbs als Markdown oder PDF unter `Notizen/<Pfad>/<Titel>`, und der Kopie für die App unter `inkhash/notes/<id>.json` und `inkhash/blobs/<sha256>` (`WorkspaceExport` im Kern).
- **Eine Sicherung importieren.** Über denselben Import wie PDF und GoodNotes. Die App erkennt die Sicherung an `inkhash-export.json`. Die Notizen kommen in den aktuellen Workspace als neue, ungesendete Notizen. Eine gleiche Notiz mit derselben ID bleibt, wie sie ist. Ist die ID von einer anderen belegt, bekommt die importierte eine neue.

Die Bibliotheken liegen in Application Support. Auf iPad und iPhone gehören sie damit zum iCloud-Backup des Geräts, wenn es eingeschaltet ist, auf dem Mac zu Time Machine. Ein Test hält fest, dass sie nicht in Caches oder tmp wandern und nicht vom Backup ausgenommen sind.

## Warum

Ohne Server lag alles nur auf dem Gerät, ein verlorenes iPad war das Ende der Notizen. Das Geräte-Backup kostet nichts und deckt den Normalfall. Der Export deckt den Rest: ein anderes Gerät, ein Umzug, ein Blick in die Notizen ohne die App.

Das Geräte-Backup ist kein Sync-Ziel. ADR 0017 und die Grenze „kein iCloud“ meinen iCloud Drive oder CloudKit als zweite Wahrheit. Das Backup stellt ein ganzes Gerät wieder her und gleicht nichts ab.

Die ZIP-Datei speichert ohne Kompression: Zeichnungen und JPEGs werden nicht kleiner, und so bleibt der Writer klein (`ZipWriter`, ohne ZIP64, also bis 4 GiB). Lesbare Dateien und die Kopie für die App liegen in einer Datei, damit niemand zwei Exporte auseinanderhalten muss.

## Nicht

- Kein PDF für Textnotizen. Markdown ist ihr Format.
- Kein Export des Papierkorbs.
- Kein Import, der Notizen ersetzt oder zusammenführt.
- Kein Live-Teilen mit anderen Personen.
- Kein automatischer Export im Hintergrund.
