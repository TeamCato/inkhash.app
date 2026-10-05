# 0022 Die Seitenleiste ist ein Baum aus Pfaden und Notizen

Status: angenommen. Auf dem iPad klappt die Leiste beim Öffnen einer Notiz weg, siehe 0030.

Ändert 0018, 0019 (Titel) und 0020 (Seitenleiste, Heute). Zwei Spalten statt drei.

## Entscheidung

**Eine Notiz liegt im Workspace und trägt einen Pfad.** Der Pfad ist das `folder` aus 0020, unverändert im Format: Segmente mit `/`, leer heißt Wurzel. Man schreibt ihn an die Notiz, als Zeile, wie einen Titel: „project xy / meeting z / thema n“. Ordner sind keine Objekte, nur das, was aus den Pfaden entsteht. `folders.json` hält weiter die leeren.

**Die Seitenleiste ist der Baum.** Unter dem Workspace-Umschalter stehen Suche und dann der Baum: Ordner aufklappbar, Notizen als Blätter darin, Notizen ohne Pfad in der Wurzel. Es gibt keine Notizliste als eigene Spalte mehr. Zwei Spalten: Baum und Blatt.

**Schlagwörter filtern den Baum.** Beginnt die Suche mit `#`, bleibt der Baum stehen und zeigt nur die Notizen, deren Schlagwort so anfängt, samt den Ordnern, in denen sie liegen. Unter dem Feld stehen dabei die passenden Schlagwörter als Kapseln zum Antippen. Es gibt keine zweite Ansicht und keine Auswahl von Schlagwörtern für die Seitenleiste.

**Flache Listen.** Textsuche, Favoriten und Papierkorb zeigen statt des Baums eine flache Liste mit Pfad, Datum und Treffer-Ausschnitt. Favoriten und Papierkorb sind Knöpfe im Fuß neben Status und Zahnrad. Heute entfällt.

**Titel und Pfad stehen oben links auf dem Blatt**, als zwei schlichte Zeilen, bei Text wie bei Handschrift. Ein Klick macht jede zum Feld. Kein Glas, nichts in der Leiste. Die Regel aus 0019 bleibt: Der Titel ist automatisch, bis man ihn setzt, und ein leeres Feld gibt ihn an den Inhalt zurück. Die erste Überschrift bleibt Teil des Textes.

**Wo es liegt.** Zugeklappte Knoten stehen in `sidebar.json` im Workspace, nur auf dem Gerät, wie `folders.json`. Nichts davon wird abgeglichen; Notiz und Vertrag ändern sich nicht.

## Warum

Die alte Leiste mischte Ziele, die man selten braucht, mit denen, in denen man lebt, und die Notizen standen in einer Spalte daneben. Ein Baum zeigt, wo etwas liegt, und die Notiz gleich dazu. Ein Pfad als Zeile ist schneller geschrieben als ein Ordner angelegt und eine Notiz hineingeschoben. Schlagwörter gehen quer über die Pfade; wer nach einem filtert, will trotzdem sehen, wo die Notizen liegen. Ein Umschalter der Ansicht und eine Auswahl von Schlagwörtern wären zwei Dinge mehr, die man bedienen muss. Ein Titel in Glas in der Leiste wollte angeschaut werden; das Blatt soll es sein.

## Nicht

Keine zweite Gliederung nach Schlagwörtern, keine verschachtelten Schlagwörter. Zugeklappte Knoten ziehen nicht zwischen Geräten um. Kein Ordner-Objekt im Vertrag.
