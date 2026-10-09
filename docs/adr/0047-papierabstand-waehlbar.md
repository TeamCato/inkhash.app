# 0047 Abstand des Papiermusters wählbar

Status: angenommen

Ändert 0042 („kein frei wählbarer Abstand“).

## Entscheidung

Der Abstand von Linien, Karos und Punkten ist pro Notiz wählbar, mit einem Schieberegler im Papier-Popover unter den Mustern. Er gilt wie Farbe und Muster für alle Seiten der Notiz.

`paper` trägt dafür optional `spacing`: ganze Seitenpunkte von 20 bis 64, in der App in Schritten von 2. Fehlt es, gilt der Standard aus 0042: 32 für Karos und Punkte, 36 für Linien. Wer den Standard wählt, löscht das Feld, damit unveränderte Notizen gleich bleiben. Leeres Papier und Textnotizen haben nie einen Abstand. Ein gewählter Abstand bleibt beim Wechsel zwischen Linien, Karos und Punkten erhalten; der Wechsel auf „Leer“ verwirft ihn.

Der Abstand liegt in Seitenkoordinaten wie das Muster selbst, steht also auf jedem Gerät an derselben Stelle der Schrift. Linien beginnen weiter bei 72, Karos und Punkte beim ersten Abstand.

Erst das Loslassen des Reglers ändert die Notiz. Während des Ziehens zeigen nur die Muster im Popover den neuen Abstand. So ist ein Zug eine Änderung zum Speichern und Abgleichen, nicht eine pro Schritt.

Der Server prüft die Form: ganze Zahl im Bereich, nur mit einem Muster. Sonst 400 `bad-request` mit `reason: "paper"`. `spacing` zählt zum Inhalt für den Retry-Vergleich.

## Warum

Wer groß oder klein schreibt, will die Linien passend zur eigenen Schrift. Ein Regler mit festen Grenzen deckt das ab, ohne Vorlagen einzuführen. Die Grenzen halten das Muster lesbar: enger als 20 Punkte wird es grau, weiter als 64 trägt es die Schrift nicht mehr.

Ein App-Stand von vor dieser Entscheidung kennt `spacing` nicht. Ändert er das Papier einer Notiz, fällt der Abstand dabei weg. Das ist hinnehmbar, weil es nur das Aussehen betrifft und sich mit einem Zug am Regler wiederherstellen lässt.

## Nicht

Kein Abstand pro Seite, kein getrennter Abstand für Zeilen und Spalten, kein freier Startpunkt der Linien, keine Angabe in Millimetern.
