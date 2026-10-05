# 0033 Das `/`-Menü auch mitten im Text

Status: angenommen

Ergänzt 0025 (ein Textfeld) und 0031 (`/Link`).

## Entscheidung

**`/` öffnet das Menü auch nach Text.** Das Menü öffnet sich, wenn vor dem Cursor `/` und höchstens ein Wort ohne Leerzeichen stehen und das `/` am Anfang des Absatzes oder nach einem Leerzeichen steht. `und/oder` und `https://…` öffnen nichts. Ein Leerzeichen schließt das Menü, Escape ebenso, bis man den Text hinter `/` ändert.

**Nach Text gibt es weniger Auswahl.** Überschriften, Code-Block und Tabelle beginnen nur eine Zeile und fehlen dort. Text, Liste, nummerierte Liste und Aufgabe ändern den ganzen Absatz und behalten seinen Text. Link, Fett, Kursiv und Code im Text wirken am Cursor.

**Die Wahl löscht nur `/` und das Suchwort**, nicht den Absatz.

## Warum

Ein Link oder eine Aufgabe fällt einem oft erst mitten im Satz ein. Bisher musste man dafür eine neue Zeile anfangen oder die Formatleiste suchen.

## Nicht

Kein `/` mitten in einem Wort, keine Befehle in Code-Blöcken und Ausschnitten.
