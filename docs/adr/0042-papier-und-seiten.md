# 0042 Papier wählen, Seiten ordnen

Status: angenommen

Ergänzt 0018 (die Notiz ist der Bildschirm) und 0029 (Papier statt Glas).

## Entscheidung

**Papier gehört zur Notiz.** Eine Notiz trägt optional `paper` mit `color` (`#RRGGBB`) und `pattern` (`blank`, `grid`, `lines`, `dots`). Fehlt es, gilt das bisherige Papier: `Ink.paper`, leer. Alle Seiten einer Handnotiz haben dasselbe Papier. Eine Textnotiz hat nur eine Farbe; ihr Muster ist immer `blank`. Wer das Standardpapier wählt, löscht das Feld, damit unveränderte Notizen gleich bleiben.

Die App bietet eine feste Palette heller Töne: Weiß (Standard), Creme, Grau, Gelb, Grün, Blau. Der Server prüft nur die Form der Farbe, nicht die Palette. Kein dunkles Papier, siehe 0029: Tinte muss auf jedem Papier lesbar bleiben.

Muster liegen in Seitenkoordinaten, damit sie auf jedem Gerät an derselben Stelle der Schrift stehen: Karos und Punkte alle 32 Punkte, Linien alle 36 Punkte ab 72. Sie füllen die ganze Seite, auch wenn sie nach unten wächst. Die Farbe füllt den ganzen Bildschirm der Notiz, auch unter dem Titel.

Das Papier ist Hintergrund, kein Inhalt der Seite: Texterkennung, Ausschnitte (0032) und Bilder auf der Seite (0028) sehen es nicht. Es zählt aber zum Inhalt für den Retry-Vergleich und für Konflikte.

**Seiten ordnen.** Ein Knopf neben dem Seitenzähler öffnet alle Seiten als Miniaturen. Antippen springt zur Seite, Ziehen verschiebt sie, das Kontextmenü verschiebt um eine Stelle oder löscht nach Rückfrage. Die letzte Seite lässt sich nicht löschen. Abschrift und Schlagwörter der Notiz folgen der neuen Reihenfolge. Ein Ausschnitt aus einer gelöschten Seite zeigt „Seite nicht gefunden“. Der Blob der Seite bleibt liegen, wie jeder Blob.

Papier und Seiten gehen auf iPad, iPhone und Mac. Der Mac zeichnet nicht, ordnet aber.

## Warum

Karo, Linien und Punkte sind für Handschrift der häufigste Wunsch, und ein Papier pro Notiz ist ohne Rückfrage „diese Seite oder alle?“ zu verstehen. Eine Übersicht als Raster lässt die Zeichenfläche frei (0018) und ist die übliche Form, Seiten zu sortieren.

## Nicht

Kein Papier pro Seite, keine eigenen Vorlagen oder PDF-Hintergründe als Papier, kein frei wählbarer Abstand, keine freie Farbe. Keine Seitenleiste neben der Zeichenfläche. Kein Papierkorb für einzelne Seiten.
