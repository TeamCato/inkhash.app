# 0049 Konflikte vergleichen

Status: angenommen

## Entscheidung

Ein Konflikt (ADR 0005) wird nicht mehr blind entschieden. Über der Notiz steht ein Hinweis mit „Vergleichen“. Der Vergleich zeigt beide Fassungen nebeneinander, bei schmaler Breite umschaltbar: Herkunft, Titel, Pfad, letzte Änderung, dann der Inhalt. Zeilen, die nur eine Fassung hat, sind markiert (`LineDiff` im Kern). Bei Text ist das der Markdown-Text, bei Handschrift die Abschrift; dazu kommen die Seiten als Miniaturen.

Danach wählt man:

- **Meine behalten**: Die Fassung des Geräts geht auf die Revision des Servers und wird hochgeladen.
- **Server-Fassung nehmen**: Die Fassung des Servers ersetzt die des Geräts.
- **Beide behalten**: Die Fassung des Geräts geht hoch. Die Fassung des Servers wird eine neue Notiz daneben, im selben Ordner, mit dem Titel und dem Zusatz „(Server)“. Der Titel gilt dann als von Hand gesetzt (ADR 0019).

„Beide behalten“ gibt es nur, wenn keine Seite gelöscht ist. Zwischen Löschen und Behalten gibt es nichts Drittes. Die Entscheidung trifft `NoteConflict.resolve` im Kern.

Wer in einer Notiz mit Konflikt weiterschreibt, behält den Konflikt. Die Fassung des Servers bleibt liegen, bis man sich entschieden hat.

## Warum

„Meine behalten“ oder „Server nehmen“, ohne die andere Fassung zu sehen, ist ein Münzwurf mit Datenverlust. Zusammenführen bleibt ausgeschlossen (ADR 0005). Zwei Notizen nebeneinander zu behalten, verliert nichts, und man räumt danach von Hand auf.

## Nicht

Kein automatisches Zusammenführen, auch nicht zeilenweise. Kein Vergleich von Strichen: Bei Handschrift zeigen die Miniaturen den Unterschied, verglichen wird nur die Abschrift.
