# 0062 Listen und Aufgaben im Textfluss

Status: angenommen. Verschachtelte Listen erlaubt durch 0086.

Ändert 0025 (Marker im linken Einzug). Ergänzt 0060 (Fälligkeit).

## Entscheidung

**Listen sind eingerückt.** Aufzählungspunkt, Nummer und Kästchen stehen dort, wo der Text der Absätze beginnt, am selben Einzug wie Titel und Pfad. Der Text eines Listeneintrags beginnt eine Stufe weiter rechts, umbrochene Zeilen ebenso. Die Marker zeichnet weiter `MarkerLayoutManager`; im Markdown ändert sich nichts.

**Aufgaben sehen aus wie in der Aufgabenliste.** Das Kästchen ist ein Quadrat in Grau, abgehakt blau gefüllt mit Haken. Der Text einer erledigten Aufgabe ist grau und durchgestrichen. Die Fälligkeit `📅 JJJJ-MM-TT` erscheint als kleine Kapsel mit Kalender und dem Tag in Worten („Heute“, „Morgen“, „20. Okt.“), blau, wenn sie heute oder früher fällig ist. Die Zeichen bleiben im Text und im Markdown; der Layout-Manager zeichnet die Kapsel an ihrer Stelle statt der Zeichen.

**Menüs am Cursor.** Das `/`-Menü und das `[[`-Menü öffnen sich unter dem Cursor, nicht am Zeilenanfang. Die Engine meldet dafür die Stelle der Einfügemarke und die Höhe der Schrift, nicht den ganzen Zeilenkasten.

## Warum

Marker im Rand ließen Listen aussehen wie Absätze mit Schmuck davor; ohne Einzug war nicht zu sehen, wo eine Liste anfängt und endet. Ein Einzug ist, wie Listen überall aussehen.

Die Aufgabenliste (0060) zeigte Aufgaben ruhiger als der Editor, der ein blaues Kästchen im Rand und das Datum als rohe Zeichen zeigte. Eine Darstellung an beiden Orten ist leichter zu lesen.

## Nicht

Keine verschachtelten Listen. Die Kapsel ist kein eigenes Element: Cursor und Auswahl laufen durch ihre Zeichen wie durch Text.
