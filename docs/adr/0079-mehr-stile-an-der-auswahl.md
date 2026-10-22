# 0079 Mehr Stile an der Auswahl

Status: angenommen. Dominik am 2026-10-22. Ändert den Abschnitt „Nicht“ von 0023 und ergänzt 0004.

## Kontext
Die Leiste an der Auswahl (0023) bot Fett, Kursiv, Code im Text und Link. Unterstreichen und Durchstreichen blieben
draußen, weil das Markdown sie nicht kannte. Gewünscht sind Unterstrichen, Durchgestrichen, Textmarker und ein Weg, die
markierten Zeilen in eine Aufzählung zu verwandeln.

## Entscheidung
**Drei neue Stile im Text, im Markdown so geschrieben, wie andere Markdown-Apps sie lesen:**

- Durchgestrichen: `~~Text~~` (GitHub-Markdown).
- Textmarker: `==Text==` (Obsidian, Typora, iA Writer, Bear).
- Unterstrichen: `<u>Text</u>`. Markdown hat kein Unterstreichen. Das HTML-Tag ist die einzige Schreibweise, die
  GitHub, Obsidian und Typora ohne Erweiterung als Unterstreichung zeigen; `++Text++` versteht kaum eine App, und `_`
  ist in Markdown schon kursiv. Inkhash liest nur genau dieses Tagpaar, sonst kein HTML.

Die drei liegen außen um Fett, Kursiv und Code und dürfen sich überlappen: `<u>~~==**Text**==~~</u>`. Ein Stil wird
für eine Strecke gleicher Stile einmal geöffnet. Ein Marker ohne Gegenstück auf derselben Zeile bleibt Text. Ein
`~~` oder `==` im Text, das als Marker gelesen würde, bekommt beim Speichern einen Backslash wie heute `*`.

**Die Leiste** zeigt neben Fett und Kursiv: Unterstrichen, Durchgestrichen, Textmarker, Code im Text, Link und, durch
einen Strich getrennt, „In Aufzählung umwandeln“. Der Knopf macht jeden markierten Absatz zu einem Listenpunkt; steht
die Auswahl schon in einer Liste, wird sie wieder Text. Auf schmalem Blatt teilen sich Unterstrichen, Durchgestrichen,
Textmarker und Code ein Menü, damit die Leiste auf das iPhone passt.

**Das Menü „Schreiben“** bekommt Unterstrichen (⌘U), Durchgestrichen (⇧⌘X) und Textmarker (⇧⌘H). Es gibt weiter nur
einen Weg, Stile zu setzen: Leiste, Menü und Kürzel lösen denselben Impuls aus (0023).

Getippt wirken die Marker wie `**`: Ist das Paar geschlossen, wird der Text gestylt und der Marker verschwindet.

## Konsequenzen
- Im Textfeld tragen eigene Schlüssel (`inkhash.underline`, `inkhash.strike`, `inkhash.highlight`) die Stile.
  `RichText.paintDecorations` zeichnet daraus Linie, Strich und Hintergrund; Links und erledigte Aufgaben nutzen
  dieselben Zeichenattribute, ohne die Stile zu verlieren.
- Kopieren nimmt die Stile im Markdown und im RTF mit (0063).
- Bestehende Notizen, die zwei `==` oder `~~` auf einer Zeile als Text enthalten, zeigen den Teil dazwischen ab jetzt
  markiert bzw. durchgestrichen.

## Nicht
Keine Farben für den Textmarker, kein weiteres HTML, keine Hoch- oder Tiefstellung.
