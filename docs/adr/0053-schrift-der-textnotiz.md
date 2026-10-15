# 0053 Schrift der Textnotiz

Status: angenommen. Wählbare Schrift und Größe geändert durch 0061.

## Entscheidung

Fließtext, Listen, Aufgaben und Tabellen einer Textnotiz stehen in der Systemschrift (SF Pro), Grundgröße 17 pt. Überschriften stehen in der System-Serif (New York), fett. Code bleibt in der Monospace der Systemschrift. Die Vorschauen außerhalb des Editors (Ausschnitte, Konfliktansicht) folgen derselben Teilung; Titel von Notizen in Listen gelten als Überschrift und bleiben Serif.

Die Zeilenhöhe liegt bei Text bei etwa dem 1,5-Fachen der Schriftgröße, bei Code beim 1,4-Fachen und bei Überschriften beim 1,2-Fachen. Erreicht wird das mit Zeilenabstand unter jeder Zeile (`lineSpacing`), nicht mit `lineHeightMultiple`. Absätze haben 10 pt Abstand nach oben, Listeneinträge 4 pt, Überschriften 28, 22 und 16 pt.

Auf iPad und iPhone folgen Schriftgrößen, Abstände und die Größe der Aufgaben-Kästchen der Textgröße des Systems (Dynamic Type), gemessen am Stil `body`. Ändert man sie bei offener Notiz, setzt der Editor alles neu. Der Mac hat kein Dynamic Type, dort gelten die Grundgrößen. Code: `EditorFont` und `NoteDocument.paragraphStyle`.

## Warum

Die Serif im ganzen Text wirkte gedrungen und altmodisch, zusammen mit einer Zeilenhöhe von etwa 1,3 wurde längerer Text schwer lesbar. Eine Grotesk mit mehr Luft liest sich auf dem Bildschirm ruhiger und passt zur übrigen Oberfläche und zum Wortzeichen. Die Serif in den Überschriften behält etwas vom Papiercharakter und trennt Gliederung deutlich vom Text.

`lineHeightMultiple` legt den zusätzlichen Raum über die Buchstaben. Dann wachsen Cursor und Auswahl nach oben, und die Markierungen von Listen und Aufgaben, die an der Grundlinie hängen, verrutschen. Zeilenabstand liegt unter der Zeile. Auf iOS wird der Cursor zusätzlich auf die Höhe der Schrift begrenzt.

Dynamic Type gehört zu einer Lese- und Schreib-App. Feste Größen ignorierten die Einstellung der Person.

## Nicht

- Keine wählbare Schrift und keine eigene Schriftgröße in der App. Die Größe kommt aus den Systemeinstellungen.
- Keine eingebetteten Schriften. Nur Systemschriften, damit nichts lizenziert oder mitgeliefert werden muss.
- Die Vorschauen in Bibliothek und Ausschnitten bleiben in fester Größe.
