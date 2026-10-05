# 0018 Die Notiz ist der Bildschirm

Status: angenommen

Ergänzt 0011 und 0012. Titel und Pfad stehen seit 0022 oben links auf dem Blatt. Eine Leiste, die nur bei markiertem Text erscheint, regelt 0023. Der Text ist seit 0025 ein einziges Textfeld.

## Entscheidung

Eine geöffnete Notiz füllt die ganze Detailfläche. Es gibt keine Blattkarte mit Schatten auf einem Schreibtisch mehr: das Blatt ist die Fläche. Titel und Werkzeuge liegen in der Leiste oder schweben am Rand, nicht über dem Text.

Text: eine Spalte bis 760 Punkt Breite, mittig, auf vollflächigem Papier. Der Titel ist die erste Überschrift.

Handschrift: die aktuelle Seite füllt die ganze Fläche und ist überall bezeichenbar. Ihre Breite passt sich der Fläche an (Zoom), die Striche bleiben in Seitenkoordinaten. Nach unten scrollt sie; schreibt man in die letzten 320 Punkte, wächst `height` um 640 Punkte, bis 10 000. Mehrere Seiten wechselt man oben in der Leiste. Die Stiftspalte steht oben links in einer eigenen Spur; Farbe und Stärke klappen neben ihr auf, nicht unten in der Mitte. Der Titel steht in der Leiste und ist dort editierbar.

Der Server-Dialog führt in einem Weg: Adresse eingeben, der Server wird von selbst geprüft, dann erscheinen nur die Felder, die es für diesen Server braucht. Beim ersten Account: Name, Passwort, Setup-Token. Danach: Name, Passwort. Ein weiterer Account über eine Einladung ist ein aufklappbarer Nebenweg. (Überholt durch 0021: Die App meldet sich nur noch an und verweist zum Einrichten auf `/admin`.)

## Warum

Die Karte mit Rand und Schatten machte die Notiz kleiner, als der Bildschirm ist. Auf dem iPad war eine 768 Punkt breite Seite auf 1032 Punkten ein Ausschnitt mit totem Rand. Die Werkzeuge in der Bildmitte unten lagen über dem Blatt. Der Server-Dialog zeigte Felder, bevor er wusste, ob der Server sie braucht.

## Nicht

Keine Werkzeugleiste über dem Text, siehe 0011. Kein Zoom durch den Nutzer auf der Handschriftseite. Die Breite bleibt 768 Punkte, nur die Höhe wächst. Der Schreibtisch-Verlauf bleibt hinter der Bibliothek.
