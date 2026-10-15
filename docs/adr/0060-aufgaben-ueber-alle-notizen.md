# 0060 Aufgaben über alle Notizen

Status: angenommen

Ergänzt 0027 (Aufgaben im Text), 0010 (Erkennung) und 0022 (Seitenleiste).

## Entscheidung

**Eine Liste aller Aufgaben.** Ein Knopf ☑︎ im Fuß der Seitenleiste zeigt auf der Detailfläche ein Blatt mit allen Aufgaben des aktuellen Workspace, aus Text und Handschrift. Es ist keine Notiz und wird nicht gespeichert, sondern bei jedem Zeigen aus den Notizen gelesen (`TaskList`). Offene Aufgaben stehen nach Fälligkeit: Überfällig, Heute, Später, Ohne Datum. Erledigte stehen zugeklappt darunter. Jede Zeile nennt ihre Notiz. Abhaken und Fälligkeit ändern wirken in der Notiz, aus der die Aufgabe kommt; Tippen auf den Text öffnet sie. Den Text einer Aufgabe ändert man nur in ihrer Notiz.

**Fälligkeit im Text.** Eine Aufgabe kann ein Datum tragen. Im Markdown steht es am Ende der Zeile als `📅 JJJJ-MM-TT`, wie im Tasks-Plugin von Obsidian: `- [ ] Angebot schicken 📅 2026-10-20`. Nur das letzte Datum am Ende gilt; ein `📅` mitten im Text ist Text. Steht der Cursor in einer Aufgabe, zeigt der Editor am Rand einen kleinen Chip: „Fällig…“ ohne Datum, sonst das Datum. Er öffnet eine Auswahl mit Heute, Morgen, Nächste Woche, einem Kalender und Entfernen. Wer will, tippt das Datum auch selbst. Ohne Datum bleibt die Aufgabe ohne.

**Aufgaben in der Handschrift.** Ein kleines, gemaltes Kästchen vor einer Zeile ist eine Aufgabe. Erkannt wird es nach dem Schreiben auf dem Gerät, zusammen mit der Abschrift (`TaskBoxes`): ein einzelner, geschlossener Strich, ungefähr quadratisch, 8 bis 60 Seitenpunkte groß, mit Ecken. Ein weiterer Strich im Kästchen hakt es ab. Der Text der Aufgabe ist die erkannte Zeile rechts daneben. Kästchen und Haken gehen nicht in die Abschrift. Die erkannten Aufgaben liegen mit Lage, Text, Zustand und Fälligkeit an der Seite (`tasks`), wie die Abschrift, und werden mit ihr abgeglichen. Abhaken in der Liste zeichnet einen Haken ins Kästchen; wieder öffnen nimmt die Striche im Kästchen weg. Die Tinte bleibt die Wahrheit, die Liste an der Seite folgt ihr. Ein Datum für eine Handschrift-Aufgabe setzt man in der Liste; es bleibt an der Aufgabe, solange ihr Kästchen an derselben Stelle steht.

## Warum

Aufgaben stehen in vielen Notizen verstreut, gebraucht werden sie zusammen. Eine eigene Aufgabenverwaltung würde die Grenze des Produkts verschieben; eine Liste, die nur liest und abhakt, bleibt bei den Notizen.

Das Datum im Markdown bleibt lesbar, wenn die Notiz woanders landet, und andere Werkzeuge verstehen es. `📅` ist eindeutig, `@` kommt in Adressen vor.

Ein gemaltes Kästchen ist, wie man auf Papier Aufgaben schreibt. Ein eigenes Werkzeug wäre zuverlässiger, aber ein Schritt mehr beim Schreiben. Nur einzelne Striche als Kästchen zu nehmen, hält Buchstaben wie O und D und große Rahmen in Skizzen heraus.

## Nicht

Keine Erinnerungen, keine Mitteilungen, keine Wiederholungen, keine Prioritäten, keine Zuständigen. Keine Uhrzeit, nur Tage. Kästchen aus mehreren Strichen werden nicht erkannt. Kein Bearbeiten des Aufgabentexts in der Liste. Der Server liest keine Aufgaben aus dem Markdown und prüft `tasks` nur auf ihre Form.
