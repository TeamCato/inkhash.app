# 0063 Kopieren und Einfügen behalten den Stil

Status: angenommen

Ergänzt 0025 (Mehrzeiliges Einfügen als Markdown).

## Entscheidung

Kopieren und Ausschneiden in einer Textnotiz legen drei Fassungen der Auswahl in die Zwischenablage:

- **Markdown im eigenen Typ** `local.inkhash.markdown`. Einfügen in eine Textnotiz liest ihn als Markdown: Fett, Kursiv, Code, Links, Überschriften, Listen, Aufgaben samt Fälligkeit, Tabellen und Ausschnitte kommen so zurück, wie sie waren, auch auf einem anderen Gerät über die Zwischenablage des Systems.
- **Markdown als reiner Text.** Andere Markdown-Apps verstehen ihn, in einfachen Textfeldern bleibt er lesbar.
- **RTF.** Mail, Pages und Notizen zeigen Fett, Kursiv und Schriftgrößen. Ohne Einzug der Notiz und ohne die gezeichneten Listenmarker.

Liegt die Auswahl in einem Absatz und umfasst nicht den ganzen, ist das Markdown nur der Text mit seinen Inline-Stilen, ohne Block: Ein halber Listenpunkt wird beim Einfügen kein neuer Listenpunkt.

Text aus anderen Apps bleibt beim Einfügen wie in 0025: reiner Text, mehrzeilig als Markdown gelesen.

## Warum

Inkhash speichert Markdown; der Stil steckt in Attributen, die das Textfeld beim Kopieren nicht mitnimmt. Ohne eigene Fassung kam beim Einfügen nur Text zurück. Markdown ist das Format, das der Editor ohnehin liest, also verliert der Weg nichts.

Fremde Formatierung beim Einfügen bleibt draußen: Schriften und Farben anderer Apps kann eine Notiz nicht speichern.

## Nicht

Kein HTML in der Zwischenablage. Kein Einfügen fremder Stile aus RTF oder HTML.
