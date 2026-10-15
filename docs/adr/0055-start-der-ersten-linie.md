# 0055 Start der ersten Linie wählbar

Status: angenommen

Ändert 0047 („kein freier Startpunkt der Linien“, „während des Ziehens zeigen nur die Muster im Popover den neuen Abstand“).

## Entscheidung

Wo die erste Zeile des Musters liegt, ist pro Notiz wählbar, mit einem zweiten Regler „Erste Linie“ im Papier-Popover unter „Abstand“. Er gilt für Linien, Karos und Punkte und verschiebt nur die Zeilen, nicht die Spalten.

`paper` trägt dafür optional `start`: ganze Seitenpunkte von 0 bis 200 von oben, in der App in Schritten von 1. Fehlt es, gilt der Standard: 72 für Linien, der Abstand für Karos und Punkte. Wer den Standard wählt, löscht das Feld, damit unveränderte Notizen gleich bleiben. Wie der Abstand bleibt ein gewählter Start beim Wechsel zwischen Linien, Karos und Punkten erhalten, und der Wechsel auf „Leer“ verwirft ihn. Leeres Papier und Textnotizen haben nie einen Start.

Während ein Regler gezogen wird, zeigt die Seite selbst das neue Muster, nicht nur die Proben im Popover. Erst das Loslassen ändert die Notiz, wie in 0047.

Der Server prüft die Form: ganze Zahl im Bereich, nur mit einem Muster. Sonst 400 `bad-request` mit `reason: "paper"`. `start` zählt zum Inhalt für den Retry-Vergleich.

## Warum

Importierte Seiten (PDF, GoodNotes, 0041) bringen Schrift mit, die auf fremden Linien geschrieben wurde. Mit Abstand allein liegen die Linien zwar gleich weit auseinander, aber neben der Schrift. Ein Start dazu reicht, um sie darunter zu legen. Ausrichten geht nur, wenn man die Schrift beim Ziehen sieht, deshalb zeigt die Seite die Vorschau.

Ein Server vor dieser Entscheidung lässt `start` bei unverschlüsselten Notizen fallen, ein App-Stand davor beim Ändern des Papiers. Wie beim Abstand betrifft das nur das Aussehen.

## Nicht

Kein Versatz der Spalten, kein Start pro Seite, kein Ausrichten durch Ziehen auf der Seite.
