# 0056 Seitenleiste aus Papier

Status: angenommen

Ergänzt 0029 (Papier statt Glas) und 0022 (Baum in der Seitenleiste).

## Entscheidung

Die Listen der Seitenleiste, Baum wie flache Listen, zeichnen keine Systemauswahl und keine Trennlinien. Die gewählte Notiz liegt als kleines Blatt auf dem Schreibtisch: `Ink.paper`, Haarlinie, weicher Schatten, Rundung 10, wie der Workspace-Umschalter darüber. Die Helfer dafür (`SidebarRow`) sind die einzige Stelle.

Zeilen sind in einer Schrift gesetzt, der Systemschrift ohne Serifen: Notizen 15 Punkt, Ordner 15 Punkt halbfett. Zeilen sind mindestens 34 Punkt hoch und stehen bündig mit Suche und Umschalter.

Vor jeder Notiz steht ihr Symbol, Stift oder Text, 14 Punkt, blau, wenn sie gewählt ist. Es steht dort, wo Ordner ihren Pfeil haben, so rücken Notizen nicht weiter ein als nötig. Unter dem Pfeil jedes aufgeklappten Ordners läuft eine Haarlinie (`Ink.hairline`) an seinem Inhalt entlang (`TreeGuides`); sie zeigt, was zu welchem Ordner gehört.

## Kopf und Fuß

Oben stehen nur zwei Zeilen: Workspace-Umschalter und „+“ nebeneinander, darunter die Suche über die volle Breite. Das Logo steht nicht mehr im Kopf, sondern klein und gedämpft links im Fuß, neben dem Symbol für den Abgleich.

Der Fuß zeigt keinen Status, solange nichts zu sagen ist: leer, „Nur auf diesem Gerät.“ oder „Abgeglichen.“ (`StatusLine.isRoutine`). Dann steht dort das Logo, und der Status liegt als Hilfetext und für VoiceOver am Symbol. Jede andere Meldung, etwa ein fehlgeschlagener Import, steht wie bisher als Text an der Stelle des Logos, bis die nächste sie ablöst.

## Warum

Die Systemliste brachte ein graues Auswahlband, eng gesetzte Serifen in 13 Punkt neben Ordnern ohne Serifen und Abstände, die zu nichts sonst in der App passten. Ein Blatt für die Auswahl ist dieselbe Sprache wie Suche, Umschalter und Leisten.

Logo, Umschalter und Suche untereinander kosteten drei Zeilen, bevor die erste Notiz kam; das Logo sagt nichts, was der Umschalter nicht schon sagt. Notizen standen eine ganze Spalte hinter dem Ordnerpfeil und sahen unter ihrem Ordner wie lose aus; die Linien zeigen die Zugehörigkeit, ohne Breite zu kosten. Der Statustext sagte meistens „Abgeglichen.“ Meldungen, die etwas bedeuten, bleiben sichtbar, weil viele Fehler nur dort erscheinen.

## Nicht

Keine eigene Liste statt `List`: Auswahl, Wischaktionen, Kontextmenüs und die Navigation auf dem iPhone bleiben beim System.
