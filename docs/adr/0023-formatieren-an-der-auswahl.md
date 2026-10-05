# 0023 Formatieren an der Auswahl

Status: angenommen. Seit 0025 hängt die Leiste an der Auswahl im einen Textfeld der Notiz; die Sitzung bekommt die Auswahl vom Editor statt von einzelnen Blöcken. Seit 0029 ist die Leiste Papier, nicht Glas.

Präzisiert 0011 und 0018: „keine Werkzeugleiste über dem Text“ gilt für feste Leisten.

## Entscheidung

**Markierter Text bekommt eine Leiste.** Sobald in einem Block Text markiert ist, schwebt direkt über diesem Block eine kleine Glasleiste: links der Blocktyp als Menü (Text, Überschriften, Listen, Aufgabe, Code), rechts Fett, Kursiv, Code im Text und Link (0024). Aktive Stile sind blau (`Ink.accent`). Hebt man die Markierung auf oder wechselt den Block, verschwindet die Leiste. Code-Blöcke zeigen keine, dort gibt es keine Inline-Stile.

**Die Leiste ist Zustand der Sitzung, nicht des Textfelds.** Beide Coordinators melden ihre Auswahl (Länge und Stile am Anfang) an die `TextSession`. Die Leiste liest nur daraus und löst dieselben Impulse aus wie das Menü „Schreiben“ und die Tastenkürzel. Es gibt keinen zweiten Weg, Stile zu setzen.

**Titel und Pfad stehen bündig mit dem Text.** Die Markerspalte links der Blöcke (Aufzählungspunkt, Nummer, Kästchen) rückt den Text ein; Kopf und Konflikt-Banner rücken gleich weit ein.

## Warum

Fett und Kursiv waren nur über Tastenkürzel, das Menü oder `/` erreichbar. Wer eine Stelle markiert, hat die Absicht schon gezeigt; der Weg zum Stil soll dann einen Klick lang sein. Eine Leiste, die nur mit einer Auswahl existiert, liegt nicht über dem Blatt, solange man liest oder schreibt. Das ist der Unterschied zu einer festen Werkzeugleiste, den 0011 und 0018 meinen.

## Nicht

Keine feste Leiste, kein Erscheinen beim bloßen Schweben über Text. Keine Stile, die das Markdown nicht kennt: Unterstreichen und Durchstreichen bleiben außen vor. Links kamen mit 0024 dazu. Keine Leiste auf der Handschriftseite.
