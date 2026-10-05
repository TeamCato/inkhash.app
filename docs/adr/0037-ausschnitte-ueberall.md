# 0037 Ausschnitte in alle Richtungen, Absätze als Auswahl, neue Notizen darunter

Status: angenommen

Ändert 0035 (Text-Ausschnitt mit `section`, Ziel der neuen Notiz, Titel). Ergänzt 0032.

## Entscheidung

**Ein Ziel für alle Ausschnitte.** Ein Ausschnitt zeigt entweder ein Rechteck einer Handschriftseite oder Text einer Textnotiz. Beide haben ein Ziel unter `inkhash://note/<id>`:

- Seite: `inkhash://note/<id>/page/<pageID>?rect=x,y,w,h` (0032)
- Text: `inkhash://note/<id>?text`, dazu `&section=<Überschrift>` oder `&from=<Anfang>&to=<Anfang>`, prozentkodiert

Dasselbe Ziel steht im Text als `![Label](Ziel)` und auf der Seite im Element `excerpt` als `link`. Damit geht jede Richtung: Handschrift in Text, Text in Handschrift, Handschrift in Handschrift, Text in Text. Das Feld `section` am Element aus 0035 entfällt; es war nie ausgeliefert.

**Absätze statt nur Gliederung.** Der Dialog zeigt eine Textnotiz so, wie sie sich liest. Ein Tipp wählt den ersten Absatz, ein zweiter den letzten; alles dazwischen gehört dazu. Gemerkt werden die ersten 60 Zeichen des ersten und des letzten Absatzes, eingeschränkt auf den Abschnitt der Überschrift darüber, wenn das nötig ist, um sie eindeutig zu finden. Findet das Ziel nicht genau die gewählten Absätze wieder, sagt der Dialog das und fügt nicht ein. Eine Überschrift allein kann für ihren ganzen Abschnitt stehen, „Ganze Notiz“ für alles. Ändert man später den Anfang eines dieser Absätze, wird der Ausschnitt zum Platzhalter.

**Neue Notiz im Dialog.** „Neue Handschrift“ (iPad, iPhone) und „Neue Textnotiz“ öffnen den vollen Editor der neuen Notiz im Dialog, mit allen Werkzeugen. „Einfügen“ nimmt alles, was dort steht; „Verwerfen“ löscht die Notiz wieder. Die Notiz hat keinen vorgegebenen Titel; er folgt dem, was man schreibt (0019), bei Handschrift über die Erkennung.

**Ablage unter der Ausgangsnotiz.** Eine neue Notiz aus dem Dialog liegt im Ordner, der wie die Ausgangsnotiz heißt, neben ihr: aus der Notiz „doc“ im Pfad „test“ wird der Pfad „test / doc“. Im Baum stehen dann die Notiz „doc“ und der Ordner „doc“ nebeneinander. Benennt man die Ausgangsnotiz später um, zieht der Ordner nicht mit.

**Kein Ausschnitt von sich selbst.** Der Dialog bietet die Notiz, in die eingefügt wird, nicht an. Ein Text-Ausschnitt zeigt keine Ausschnitte, die in seiner Quelle stehen.

## Warum

Die Richtung war bisher an die Art der Notiz gebunden, ohne dass es dafür einen Grund gab. Ein gemeinsames Ziel macht beide Seiten gleich und hält den Vertrag klein. Absätze sind das, was man beim Lesen meint; eine Gliederung allein reicht selten.

## Nicht

Keine versteckten Block-IDs im Markdown; deshalb die Anker über den Anfang des Absatzes. Kein Ordner, der der Ausgangsnotiz beim Umbenennen folgt. Keine Ausschnitte über Workspaces hinweg.
