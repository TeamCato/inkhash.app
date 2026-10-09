# 0048 Erstellungsdatum der Notiz

Status: angenommen

## Entscheidung

Eine Notiz trägt `createdAt`, einen Zeitstempel in UTC im selben Format wie `updatedAt`. Er steht im Kopf des Blatts rechts neben Titel und Pfad, mit Datum und Uhrzeit, und lässt sich dort per Klick ändern.

Anders als `updatedAt` setzt der Client `createdAt`, nicht der Server: beim Anlegen auf den Moment des Anlegens, danach nur, wenn jemand es von Hand ändert. Es wird abgeglichen und zählt zum Inhalt für den Retry-Vergleich.

Notizen von vor dieser Entscheidung haben kein `createdAt`. Für sie gilt `updatedAt` als Erstellungsdatum. Die App schreibt diesen Wert bei der nächsten Änderung fest (`Note.touch`), damit das Datum nicht mit jeder Änderung mitwandert.

Ändert man das Datum, ist das eine Änderung wie jede andere: `updatedAt` rückt nach, die Notiz geht zum Server.

## Warum

Der Tag, an dem eine Notiz entstand, ordnet Besprechungen, Retros und Workshops besser als die letzte Änderung. Änderbar muss es sein, weil Notizen oft nachgetragen oder aus anderen Apps übernommen werden.

`updatedAt` als Rückfall ist für alte Notizen zu spät, aber nie leer und nie in der Zukunft. Wer es genauer weiß, korrigiert es von Hand.

Der Server lässt ein fehlendes `createdAt` beim `PUT` nicht weg, sondern behält das gespeicherte. So verliert eine Notiz ihr Datum nicht, wenn ein App-Stand von vorher sie bearbeitet.

## Nicht

Keine Sortierung nach Erstellungsdatum, kein Filter danach, keine Zeitzone an der Notiz.
