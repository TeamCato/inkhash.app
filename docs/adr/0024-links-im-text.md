# 0024 Links im Text

Status: angenommen. Links auf Notizen ergänzt durch 0027, `/Link` und Prüfung der Ziele durch 0031. Die Nummer 0024 trägt auch „Import ist Konvertierung“; beide gelten.

Ergänzt 0004 (Markdown) und 0023 (Formatleiste).

## Entscheidung

**Markdown kennt `[Text](Ziel)`.** Ein `InlineSpan` trägt neben fett, kursiv und Code ein optionales `link`. Der Codec liest `[Text](Ziel)` und schreibt es zurück; benachbarte Spans mit demselben Ziel sind ein Link mit Stilen darin: `[**fett** normal](ziel)`. Das Label darf keine eckige Klammer enthalten, das Ziel kein Leerzeichen und keine runde Klammer. Fehlt eines davon oder ist leer, bleibt alles Text. Ein `[` im Text wird beim Schreiben escaped.

**Im Editor ist ein Link blau und unterstrichen, aber kein `.link`.** Das Ziel liegt in einem eigenen Attribut (`.inkhashLink`). Ein einfacher Klick setzt den Cursor wie überall; auf dem Mac zeigt der Zeiger eine Hand und ein Tooltip das Ziel, Cmd+Klick öffnet es. Auf dem iPad öffnet man ihn über das Linkfeld der Formatleiste.

**Setzen und lösen über die Formatleiste.** Der Link-Knopf öffnet ein kleines Feld für das Ziel. Setzen legt den Link auf die Markierung, Entfernen nimmt ihn weg, ein leeres Feld ebenso. Cmd+K öffnet dasselbe Feld, wenn Text markiert ist. Ohne Schema wird `https://` vorangestellt.

**Tippt man `[Text](Ziel)` von Hand**, wird es wie `**fett**` verbraucht, sobald die schließende Klammer da ist.

## Warum

Notizen verweisen auf Dinge. Ohne Links landet eine URL als nackter Text im Blatt, und der Codec würde die Klammern beim nächsten Speichern escapen oder zerlegen. Das System-`.link` würde beim Klick sofort öffnen und das Bearbeiten des Linktexts erschweren.

## Nicht

Keine Referenz-Links (`[text][1]`), keine Autolinks aus nackten URLs, keine Links auf andere Notizen, keine Vorschau. Unterstreichen und Durchstreichen bleiben außen vor, das Markdown kennt sie nicht.
