# 0010 Suche und Schlagwörter ohne Modell

Status: angenommen

## Entscheidung

Die Bibliothek sucht von Anfang an über Titel, Markdown, Handschrift-Abschrift und Tags. Die Abschrift entsteht auf dem Gerät mit Vision, ohne Sprachkorrektur. Tags werden aus dem Text und aus einem `#` neben einem Wort gelesen und mit der Notiz synchronisiert.

Der Vergleich ist tolerant, aber nicht semantisch: Normalisierung, Präfix ab drei Zeichen, kleine Edit-Distanz, Wortreihenfolge egal, Tag auch ohne `#`. Jedes Wort der Anfrage muss irgendwo treffen.

## Warum

Handschrift ist sonst nicht wiederfindbar, und die Erkennung trifft den Wortlaut nicht immer. Ein Embedding oder ein Assistent würde die Grenze des Produkts verschieben und auf den Server oder in ein Modell gehören, das wir nicht betreiben wollen.

## Nicht

Keine Synonyme. Kein Such-Endpunkt. Keine Bilder an den Server. Eine fehlgeschlagene Erkennung löscht keine schon vorhandene Abschrift.
