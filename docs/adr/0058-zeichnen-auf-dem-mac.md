# 0058 Zeichnen auf dem Mac

Status: angenommen

Ändert 0035 („auf dem Mac gibt es diesen Weg nicht, weil dort nicht gezeichnet wird“) und die Grenze in `AGENTS.md`, dass der Mac nur zeigt.

## Entscheidung

Auf dem Mac zeichnet man mit Maus oder Trackpad auf Handschriftseiten. Eine schmale Werkzeugleiste am linken Rand bietet die vier Stifte, einen Radierer, die Farben und Stärken der iPad-Leiste. Der Radierer nimmt ganze Striche. ⌘Z nimmt einen Strich oder einen Radierzug zurück.

macOS PencilKit hat kein `PKCanvasView`, kann aber `PKStroke` bauen und rendern. `InkSketch` macht aus einem Mauszug einen Strich in Seitenpunkten, mit gleichem Druck und gleicher Breite über die ganze Länge. Er landet in derselben Zeichnung wie Striche vom iPad, gleicht sich genauso ab und wird genauso gelesen. Die Seite wächst nach unten wie auf dem iPad.

Im Ausschnitt-Dialog einer Textnotiz gibt es auf dem Mac jetzt auch „Neue Handschrift“: grob mit der Maus skizzieren, als Ausschnitt einfügen, später auf dem iPad sauber nachzeichnen. Der Ausschnitt zeigt dann, was dort steht.

Bilder, Formen, Tape, Auswahl und Masken gibt es auf dem Mac weiter nicht. Elemente werden gezeigt, nicht bearbeitet.

## Warum

Kleine Änderungen an einer Handschrift und eine schnelle Skizze beim Tippen sollen nicht am iPad hängen. Eine Maus ersetzt keinen Stift, für eine Korrektur oder einen Entwurf reicht sie.

## Nicht

Kein Druck oder Neigung aus dem Trackpad, kein Pixel-Radierer, keine Bearbeitung von Elementen, keine Auswahl von Strichen auf dem Mac.
