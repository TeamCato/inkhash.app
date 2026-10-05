# 0041 GoodNotes-Datei lesen

Status: angenommen. Hebt in ADR 0024 „Keine `.goodnotes`-Datei lesen“ und „Die Quelle ist der PDF-Export“ auf. Der Rest von 0024 gilt weiter.

## Entscheidung

**Inkhash liest `.goodnotes`-Dateien direkt.** „PDF oder GoodNotes importieren…“ nimmt beides. Ob es ein PDF oder ein GoodNotes-Notizbuch ist, entscheiden die ersten Bytes (`%PDF` oder `PK`), nicht die Endung. Der Typ heißt `com.goodnotesapp.goodnotes.v5` und steht als importierter Typ in beiden `Info.plist`.

**GoodNotes 5, 6 und 7 schreiben denselben Container.** Unterscheiden lassen sie sich nur an der Schema-Nummer in `schema.pb` (24, 25, 35). Der Leser prüft sie nicht und liest, was er erkennt. Unbekannte Strichformate fallen einzeln weg, nicht die ganze Datei.

**Der Import läuft auf dem Gerät, wie in 0024.** `GoodNotes` im Kern liest, `InkImport` in der App macht daraus `PKDrawing` und Seitenelemente. Vertrag, Server und Sync ändern sich nicht. Eine Datei wird eine Notiz, über 100 Seiten mehrere. Der Titel ist der Dateiname.

## Was herüberkommt

- **Striche** mit Farbe und Breite. Kugelschreiber wird `.monoline`, Füller und Pinsel `.pen` mit Breite pro Punkt, Marker `.monoline`, Textmarker `.marker`, Bleistift `.pencil` mit geringer Deckkraft. Die Größen der PencilKit-Punkte sind gemessen, siehe `InkImport.pkStroke`.
- **Formen** aus dem Formwerkzeug als Striche: Linie, Kurve, Rechteck, Ellipse.
- **Bilder und Sticker** als `image`-Elemente ohne Rahmen (ADR 0028), als JPEG auf Weiß.
- **Seiten eines importierten PDFs** (Folien, Arbeitsblätter) als `image`-Element über die ganze Seite, ganz unten. Das ist kein Seitenhintergrund im Sinne von 0024: kein neues Feld, kein neuer Blob-Typ. Man kann es auswählen und verschieben wie jedes Foto.
- **Seitenreihenfolge** aus den Schlüsseln im Ereignisprotokoll. Gelöschte Seiten bleiben weg.

## Was verloren geht

Textfelder (RTF und das neuere Textelement), Haftnotizen, Füllungen geschlossener Formen, Audio, Lesezeichen und Links. Die App meldet nach dem Import, wie viele Elemente fehlen. GoodNotes' eigene Papiere (Linien, Karos, Punkte) kommen nicht mit, Inkhash hat sein eigenes Blatt. Erkannt werden sie am Namen `<UUID>_<art>_<n>_<n> - <titel>` oder am Producer `svg2pdf` eines einseitigen PDFs. Ein Bild über einem Textmarker liegt danach darunter, weil Elemente in Inkhash immer unter der Tinte liegen. Druck und Neigung des Bleistifts fallen weg.

## Das Format

Undokumentiert. Die Struktur folgt öffentlichem Reverse Engineering unter MIT-Lizenz, vor allem `jakubfabrici/notability-goodnotes` (`docs/goodnotes-*.md`, `gnnote/tpl.py`) und `cable729/inkterop`. Code ist nicht übernommen; GPL-Projekte wie `goodparse` sind nur gelesen. Kurz:

- ZIP mit `index.notes.pb`, `index.events.pb`, `index.attachments.pb`, `notes/<UUID>` und `attachments/<UUID>`. Jede `.pb`-Datei und jede Seite ist eine Folge `<varint Länge><Protobuf-Nachricht>`.
- Im Ereignisprotokoll ist die Feldnummer der Ereignistyp: `#2` Papier, `#54` Seite angelegt, `#3` neu gebunden, `#55` verschoben, `#56` gelöscht, `#30`/`#31` Titel.
- Die Notizschicht einer Seite hat die UUID der Seite plus eins, als 128-Bit-Zahl mit Übertrag.
- Ein Strich ist Apples LZ4-Rahmen (`bv41`, `bv4-`, `bv4$`) um ein TPL-Abbild. Koordinaten sind Canvas-Einheiten, 132/72 pro PDF-Punkt, y nach unten. Fünf Formatstrings sind bekannt (`GoodNotesGeometry`).
- Die Seitengröße ist die MediaBox des Papier-PDFs.

Geprüft gegen 14 Dateien aus GoodNotes 5 und 6 (iPad und Mac) und gegen GoodNotes' eigene PDF-Exporte derselben Dateien: gleiche Seiten, Striche und Koordinaten wie die Referenz. Der Leser übersteht zufällig beschädigte Dateien ohne Absturz. Im Repo liegt eine CC0-Datei aus inkterop als Fixture (`docs/fixtures/goodnotes-mixed-pens.goodnotes`).

## Warum jetzt doch

0024 wählte den PDF-Export, weil er stabil schien. Zwei Dinge sprechen dagegen. Die Datei ist, was Nutzer haben; ein PDF-Export pro Notizbuch ist eine Hürde. Und GoodNotes legt die Tinte im PDF-Export als Annotationen ab, die `PDFInk` nicht liest: Bei den geprüften Exporten kam fast nichts an. Das Format ist seit GoodNotes 5 stabil, und es gibt mittlerweile genug unabhängige Beschreibungen, die übereinstimmen.

## Risiko

GoodNotes kann das Format ändern. Dann fallen unbekannte Striche weg, die Datei bricht nicht. Die AGB von GoodNotes schränken Reverse Engineering ein. Inkhash liest nur Dateien, die der Nutzer selbst auswählt, schreibt keine und spricht nicht mit GoodNotes.

## Nicht

Kein Export nach GoodNotes. Keine Textfelder als Text. Keine GoodNotes-Papiere als Bild. Kein Import auf dem Server.

## Offen

- Der PDF-Weg aus 0024 sollte Annotationen (`/Annots`, Appearance Streams) und Form-XObjects lesen, sonst bleibt ein GoodNotes-PDF-Export fast leer.
- Textfelder könnten als Textelement auf der Seite herüberkommen, sobald es eines gibt.
- Import läuft auf dem Hauptthread. Bei großen Notizbüchern mit vielen PDF-Seiten braucht er eine Warteschlange im Hintergrund.
