# 0024 Import ist Konvertierung, kein Hintergrund

Status: angenommen, Spike. Fotos auf der Seite gibt es seit 0028. Die Nummer 0024 trägt auch „Links im Text“; beide gelten.

## Entscheidung

**Fremde Notizen kommen als Striche herein, nicht als Bild.** Ein Import liest die Vektorpfade aus einem PDF, wie es GoodNotes 6 exportiert, und macht daraus pro Seite eine `PKDrawing`. Das Ergebnis ist eine gewöhnliche `ink`-Notiz: Seiten, Blobs, Abschrift durch die eigene Erkennung, Schlagwörter aus der Abschrift. Nichts am Vertrag, am Server oder am Sync ändert sich.

**Die Quelle ist der PDF-Export, nicht die `.goodnotes`-Datei.** Das Format von GoodNotes ist undokumentiert und hat sich zwischen Version 5 und 6 geändert. Ob eine `.goodnotes`-Datei aus 5 oder 6 stammt, lässt sich am Inhalt des ZIPs erkennen, aber die Strukturen darin zu lesen ist Reverse Engineering ohne Boden. Der PDF-Export ist dagegen vom Nutzer selbst ausgelöst, versioniert in Apples PDF-Bibliothek und bleibt lesbar, wenn GoodNotes das Format wechselt.

**Der Import läuft auf dem Gerät.** Lesen, Konvertieren, Erkennen, alles lokal. Der Server sieht am Ende Blobs und eine Notiz, wie bei jeder anderen.

**Eine Datei wird eine Notiz.** Der Titel ist der Dateiname ohne Endung und gilt als gesetzt (ADR 0019). Die Notiz landet im gerade gewählten Ordner. Seiten behalten ihr Seitenverhältnis und werden auf die Standardbreite skaliert.

## Was dabei verloren geht

Druck und veränderliche Strichstärke. GoodNotes schreibt den Füller als gefüllte Flächen ins PDF, den Kugelschreiber als gestrichelte Pfade. Aus einer Fläche wird hier die Mittellinie mit mittlerer Breite (`PDFInkStroke.centerline`), wenn die Fläche wie ein Band aussieht; sonst der Umriss. Papiervorlagen (Linien, Karos), die GoodNotes als Pfade mitgibt, fliegen heraus, wenn derselbe Pfad auf mehr als einer Seite vorkommt (`PDFInk.withoutRepeated`). Bilder, Sticker, Textfelder, Lesezeichen und Outlines fallen weg. Eine Seite ohne Vektoren bleibt leer.

## Warum nicht ein Bild unter der Seite

Ein Seitenhintergrund wäre ein zweiter Blob pro Seite, ein neues Feld im Vertrag, ein Renderpfad auf dem Mac und die Tür zu „PDF annotieren“. PRODUCT sagt: keine Fotos. Ein Import, der die Grenze des Produkts verschiebt, ist kein Import, sondern ein anderes Produkt. Wer das will, schreibt eine neue ADR und hebt diese auf.

## Nicht

Keine `.goodnotes`-Datei lesen. Keine Hintergrundbilder. Kein Import von Textnotizen aus PDFs; GoodNotes-Text wird zu Strichen oder fällt weg. Kein Import auf dem Server. Keine Form-XObjects im ersten Schritt: Pfade in eingebetteten Formularen werden gezählt, nicht gelesen (`PDFInkPage.skippedForms`). Gedrehte Seiten (`/Rotate`) werden nicht gedreht.

## Offen, nach dem Spike

- Mit echten GoodNotes-6-Exporten prüfen: Füller als Fläche oder Pfad? Liegt die Vorlage in einem XObject? Dann Formulare lesen.
- Erkennung läuft erst beim Öffnen der Notiz (`InkNoteView.onAppear`). Bei hundert Seiten braucht es eine Warteschlange im Hintergrund und einen Status in der Bibliothek.
- Doppelter Import derselben Datei: SHA-256 der Quelle merken und nachfragen.
