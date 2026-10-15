# 0059 Rückgängig und Wiederholen als Knöpfe

Status: angenommen

Ergänzt 0023 (Formatleiste), 0025 (ein Textfeld) und 0058 (Zeichnen auf dem Mac).

## Entscheidung

Beide Editoren haben in ihrer Leiste oben zwei Knöpfe: Rückgängig (↶) und Wiederholen (↷). Sie stehen vor den übrigen Knöpfen der Notiz und sind ausgegraut, solange es nichts zurückzunehmen oder zu wiederholen gibt. Gesten, ⌘Z und ⇧⌘Z gehen weiter wie bisher; die Knöpfe benutzen denselben Verlauf.

Der Verlauf ist der `UndoManager` des Editors: im Text der des Textfelds, auf dem iPad der des `PKCanvasView`, auf dem Mac der des Fensters. `UndoHistory` folgt ihm und sagt den Knöpfen, was gerade geht. Ein Editor hat nie zwei Verläufe nebeneinander.

Im Text auf iPad und iPhone führt das Textfeld seinen Verlauf selbst, in einem eigenen `UndoManager`. Jede Änderung der `EditorEngine`, etwa ein Kürzel wie `# `, eine Formatierung oder eine Tabellenzelle, ist ein Schritt. Tippen ist ein Schritt pro Lauf: Er beginnt mit dem ersten Zeichen und endet mit einer neuen Zeile, einem Sprung des Cursors oder einer Änderung der Engine. Jeder Schritt legt den ganzen Text samt Auswahl zurück, wie er davor war, und beim Zurücknehmen den Schritt nach vorn. Vorher wurde der Verlauf bei jeder Änderung der Engine gelöscht. Auf dem Mac gehen diese Änderungen schon über `shouldChangeText` in den Verlauf des Textfelds; dort bleibt es beim System.

## Warum

Ohne Tastatur gab es Rückgängig nur über Gesten, die man kennen muss, und Wiederholen fast gar nicht. Im Text auf dem iPad löschte jede Formatierung den Verlauf, man konnte also nur bis zur letzten Formatierung zurück.

Die Schritte von UIKit lassen sich nicht mit eigenen mischen: UIKit wirft seine Tipp-Schritte weg, sobald jemand anderes die Zeichen ändert (PITFALLS P-060). Also gehören alle Schritte dem Editor. Den ganzen Text zurückzulegen statt nur den geänderten Bereich ist einfach und kann nicht danebenliegen. Notizen sind klein genug, dass die Kopie nicht ins Gewicht fällt; der Verlauf hält höchstens 100 Schritte.

## Nicht

Kein Verlauf über das Schließen der Notiz hinaus und keine Versionen einer Notiz. Rückgängig gilt für die geöffnete Notiz, solange sie offen ist.
