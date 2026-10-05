# 0034 Der Titel einer Handschrift kommt aus der Stiftschrift

Status: angenommen

Ergänzt 0019 (Titel automatisch) und 0010 (Suche).

## Entscheidung

Die Erkennung liest Striche des Markers getrennt von Füller, Stift und Strich. Die Abschrift einer Seite beginnt mit dem, was die Stifte geschrieben haben; der Marker-Text folgt in eigenen Zeilen. Der automatische Titel ist weiterhin die erste Zeile der Abschrift und kommt damit nie aus einer Markierung. Schlagwörter gelten aus beiden.

Ohne Marker-Striche bleibt alles wie bisher: eine Erkennung über die ganze Seite.

## Warum

Mit dem Marker hebt man hervor, man schreibt damit selten den Anfang einer Seite. Über Text gezogen las Vision die Markierung mit oder vor dem Text, und der Titel wurde zu einem Wortsalat.

## Nicht

Kein eigenes Feld für den Titel im Speicherformat (0019). Die Reihenfolge in der Abschrift ist nicht mehr streng die Lesereihenfolge der Seite, wenn Marker-Text darin vorkommt.
