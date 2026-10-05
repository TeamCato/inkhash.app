# 0028 Bilder, Formen, Tape und Links auf der Handschriftseite

Status: angenommen. Text-Ausschnitte (`excerpt`) ergänzt durch 0035; „kein Textelement“ gilt weiter für bearbeitbaren Text.

Ändert PRODUCT.md („Formen, Klebezettel und Fotos gibt es nicht“), 0012 (Stiftwerkzeuge) und 0018 (Werkzeugspalte). Übernimmt das Modell des Scweble-Editors.

## Entscheidung

**Eine Seite hat Elemente.** `InkPage.elements` ist eine Liste, flach wie bei Scweble: `id`, `kind`, Mittelpunkt `x`/`y`, `width`/`height`, `rotation` (Bogenmaß), `z`, dazu je nach Art:

- `image`: `blob` (SHA-256 eines JPEG, wie Zeichnungen im Blob-Speicher), `frame` `{ style: none|solid|polaroid, color, width, shadow }`, `mask` `{ kind: circle|rectangle|freehand, points }` mit Punkten 0…1 im Bildbereich.
- `shape`: `shape` `line|rect|ellipse|triangle`, `stroke` (Farbe oder null), `strokeWidth`, `fill` (Farbe oder null), `fillOpacity`.
- `tape`: `color`, durchscheinend gezeichnet.
- `link`: eine Fläche ohne eigenes Aussehen, nur mit Ziel.

Jedes Element kann `link` tragen: `https://…` oder `inkhash://note/<id>` (0027). Farben sind `#RRGGBB`. Koordinaten sind Seitenkoordinaten wie die Striche. Fehlt `elements`, ist die Liste leer.

**Schichten.** Elemente liegen unter der Tinte: man schreibt auf Bilder und Tape. Die Zeichenfläche ist durchsichtig. Auf dem Mac werden Elemente gezeigt, nicht bearbeitet.

**Auswahl.** Das Werkzeug „Auswahl“ zieht ein Rechteck auf. Es wählt Elemente nach ihrem Mittelpunkt und Striche nach dem Mittelpunkt ihrer Begrenzung, wie in Scweble. Die Auswahl lässt sich verschieben, skalieren und löschen. „Verlinken“ setzt den Link auf ausgewählte Elemente; enthält die Auswahl Tinte, entsteht eine Linkfläche über ihr. Ein einzelnes Element hat eine Leiste mit Rahmen, Maske, Farbe, Link, nach vorn/hinten und Löschen.

**Links folgen.** Verlinkte Elemente und Linkflächen tragen oben rechts ein kleines Link-Zeichen. Ein Tipp darauf öffnet das Ziel. Das gilt in jedem Werkzeug, auf iPad, iPhone und Mac.

**Werkzeugleiste.** Die Leiste liegt am linken Rand und ist immer ganz offen: Werkzeuge, darunter Farben, eigene Farbe (System-Farbwähler, gemerkt bis zwölf), Stärke. Kein zweiter Tipp mehr, um Optionen zu öffnen. Bei kompakter Breite liegt dieselbe Leiste unten (0026). Werkzeuge: Füller, Stift, Strich, Marker, Radierer, Form, Tape, Bild, Auswahl.

**Bilder** kommen aus der Fotomediathek oder aus Dateien, werden auf höchstens 2000 Pixel verkleinert, als JPEG gespeichert und wie Zeichnungs-Blobs abgeglichen.

**Vertrag.** `elements` gehört zur Seite und zum Inhalt für den Retry-Vergleich. Der Server prüft die Form. Bild-Blobs werden vor der Notiz hochgeladen wie Zeichnungen.

## Warum

Notizen mit Handschrift brauchen Fotos von Tafeln, Belegen und Skizzen, und eine Möglichkeit, auf andere Notizen zu zeigen. Scweble hat dafür ein erprobtes Modell; ein zweites zu erfinden wäre Pflege ohne Gewinn. Optionen, die erst nach einem zweiten Tipp erscheinen, wurden nicht gefunden.

## Nicht

Keine Klebezettel, kein Textelement, keine Ebenen, kein Zuschneiden außer über Masken, kein Lineal. Eine ältere App, die `elements` nicht kennt, verliert sie beim nächsten Schreiben; alle Geräte müssen aktualisiert werden (wie P-031).
