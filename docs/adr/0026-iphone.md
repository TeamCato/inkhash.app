# 0026 Das iPhone ist ein Ziel

Status: angenommen. „Glas“ heißt seit 0029 Papier.

Ändert die Grenze „Das iPad-Ziel ist iPad, nicht iPhone“ aus AGENTS.md. Ergänzt 0018 und 0022.

## Entscheidung

**Eine iOS-App für iPad und iPhone.** Das Ziel `Inkhash` läuft auf beiden (`TARGETED_DEVICE_FAMILY` 1,2). Die Bundle-ID bleibt `local.inkhash.ipad`, damit installierte Apps, Bibliothek und Schlüsselbund erhalten bleiben. Auf dem iPhone nur Hochformat.

**Die Breite entscheidet, nicht das Gerät.** Bei kompakter Breite (iPhone, schmales iPad-Fenster) klappt die geteilte Ansicht zu einem Stapel: erst der Baum, ein Tipp öffnet die Notiz, Zurück führt zum Baum. Der leere Platzhalter erscheint nur bei regulärer Breite. Blätter, Seiten und Notizen ändern sich nicht.

**Text** hat bei kompakter Breite 16 Punkt Rand statt 36. Spalte, Marker, Formatleiste und `/`-Menü bleiben gleich.

**Handschrift** bleibt eine 768 Punkt breite Seite, eingepasst in die Breite (0018). Bei kompakter Breite liegen die Werkzeuge als waagrechte Glasleiste unten statt als Spalte links; Farbe und Stärke klappen darüber auf. Auf dem iPhone zeichnet der Finger immer, zwei Finger scrollen; der Schalter „Mit dem Finger“ fehlt dort.

**Dialoge** haben keine Mindestbreite mehr über der Bildschirmbreite eines iPhones.

## Warum

Notizen nachlesen, kurz etwas tippen oder abhaken passiert unterwegs, und dafür ist das iPhone da. Der Code ist zum größten Teil schon SwiftUI und kennt keine Gerätefamilie. Eine zweite App oder ein eigenes Layout fürs iPhone wären mehr Pflege für denselben Inhalt.

## Nicht

Keine eigene iPhone-Bundle-ID, kein Querformat auf dem iPhone, keine schmalere Handschriftseite und kein Zoom durch den Nutzer. Das Schreiben mit dem Stift bleibt für das iPad gedacht; auf dem iPhone ist Handschrift mit dem Finger ein Notbehelf.
