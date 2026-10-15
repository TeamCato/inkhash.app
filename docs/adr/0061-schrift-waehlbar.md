# 0061 Schrift und Größe der Textnotiz wählbar

Status: angenommen

Ändert 0053 im Punkt „Keine wählbare Schrift und keine eigene Schriftgröße“.

## Entscheidung

In den Einstellungen gibt es ganz oben einen Abschnitt „Text“ mit Schrift und Größe; auf dem Mac steht er auch unter *Inkhash → Einstellungen…* (⌘,). Er gilt für alle Textnotizen auf diesem Gerät und wird nicht abgeglichen.

- **Schrift:** Standard (Systemschrift), Serif (New York), Abgerundet (SF Rounded) oder Monospace (SF Mono). Sie gilt für Fließtext, Listen, Aufgaben und Tabellen. Überschriften bleiben in der Serif, Code in der Monospace.
- **Größe:** Grundgröße des Fließtexts von 13 bis 24 pt, Standard 17. Überschriften, Code, Tabellen, Abstände und Kästchen wachsen im selben Verhältnis mit. Auf iPad und iPhone kommt Dynamic Type darauf, wie in 0053.

Ohne Wahl bleibt alles wie in 0053. Eine Änderung gilt sofort, auch in einer offenen Notiz. Gespeichert sind beide Werte in den Einstellungen des Geräts (`TextAppearance`, `UserDefaults`).

## Warum

Was sich angenehm liest, hängt von Augen, Bildschirm und Abstand ab. Dynamic Type gibt es auf dem Mac nicht, und es ändert die Schrift aller Apps zugleich.

Nur Systemschriften, damit nichts lizenziert oder mitgeliefert werden muss. Pro Gerät, weil der Mac am Schreibtisch eine andere Größe braucht als das iPhone in der Hand.

## Nicht

Keine Schrift pro Notiz, keine eingebetteten Schriften, keine eigene Schrift für Überschriften. Die Vorschauen in Bibliothek und Ausschnitten bleiben in fester Größe.
