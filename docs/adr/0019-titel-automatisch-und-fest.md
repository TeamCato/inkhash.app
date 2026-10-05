# 0019 Jede Notiz hat einen Titel: automatisch, bis man ihn setzt

Status: angenommen. Ort des Titels geändert durch 0022: oben links auf dem Blatt, nicht in der Leiste.

## Entscheidung

Jede Notiz hat einen Titel, und die Bibliothek zeigt ihn. Er steht klein in der Leiste, bei Text wie bei Handschrift, und wird dort per Klick geändert. Über dem Text steht kein eigenes Titelfeld; die erste Überschrift ist Teil des Textes.

Solange niemand ihn setzt, ist er automatisch: bei Text die erste Überschrift, sonst die erste nicht leere Zeile; bei Handschrift die erste Zeile der Abschrift. Ein getippter Titel bleibt stehen, egal wie sich der Text ändert. Leert man das Feld, wird er wieder automatisch.

Es gibt kein Feld dafür im Speicherformat. Ein Titel ist automatisch, wenn er leer ist oder bei Text genau dem entspricht, was der Text ergeben würde (`Note.hasAutomaticTitle`). Jedes Gerät kommt so zum selben Schluss, auch ein älteres.

## Warum

Eine Liste voller „Ohne Titel“ hilft niemandem, und ein Titel, den man nicht ändern kann, auch nicht. Ein zusätzliches Flag hätte Vertrag, Server und Fixtures geändert, ohne mehr zu können.

## Nicht

Setzt jemand von Hand genau den Titel, den der Text ergibt, folgt er danach wieder dem Text. Das ist gewollt und kein Fehler.
