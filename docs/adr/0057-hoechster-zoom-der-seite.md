# 0057 Zoom der Handschriftseite

Status: angenommen

Ändert 0018 („die aktuelle Seite füllt die ganze Fläche und ist überall bezeichenbar. Ihre Breite passt sich der Fläche an“, „kein Zoom durch den Nutzer“).

## Entscheidung

Eine Handschriftseite öffnet eingepasst: Sie passt sich der Breite der Fläche an, aber höchstens bis zum Maßstab 1,35, knapp über dem eines 13-Zoll-iPads hochkant (1032 von 768 Punkten), das so weiter die volle Breite füllt (`PageGeometry.maxScale`). Ist die Fläche breiter, etwa ein iPad quer oder ein breites Mac-Fenster, steht die Seite in diesem Maßstab in der Mitte. Daneben liegt die Papierfarbe der Notiz; zwei leise gepunktete Linien zeigen, wo die Seite endet (0070).

Auf dem iPad zoomt man mit zwei Fingern weiter hinein, bis zum Vierfachen dieses Maßstabs, um Kleines zu zeichnen. Weiter heraus als eingepasst geht es nicht. Dreht man das Gerät oder ändert sich die Breite, steht die Seite wieder eingepasst; eine andere Seite öffnet ebenso. Der Zoom wird nicht gespeichert. Der Mac zeigt die Seite nur und zoomt nicht.

Die Zeichenfläche reicht über die ganze Breite; die Seite steht darin über Einzüge in der Mitte, und hineingezoomt nutzt sie den ganzen Bildschirm. Bezeichenbar ist nur die Seite, nicht der Rand: Ein Strich, der neben der Seite beginnt, zeichnet nicht, Scrollen und Zoomen gehen dort aber. Auf dem Mac scrollt auch der Rand. Die Seite bleibt 768 Punkte breit, Striche bleiben in Seitenkoordinaten. Am Speicherformat und am Server ändert sich nichts.

## Warum

Bei voller Breite wuchs die Schrift im Querformat auf das 1,8-Fache und auf dem Mac mit jedem breiteren Fenster weiter. So sieht dieselbe Seite quer wie hochkant gleich groß aus. Wer etwas Kleines zeichnen muss, braucht trotzdem mehr; PencilKit zoomt dafür selbst, und die Striche bleiben scharf. Textnotizen machen es mit ihrer Spalte bis 760 Punkte schon so.

## Nicht

Keine Papierformate wie A4: Die Seite wächst nach unten, ein Einpassen in die Höhe ergäbe keinen Sinn. Kein Herauszoomen unter die eingepasste Breite, kein gespeicherter Zoom, keine breitere Seite im Querformat, kein Schreiben im Rand.
