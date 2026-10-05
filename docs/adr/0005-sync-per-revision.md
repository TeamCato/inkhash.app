# 0005 Sync per Revision

Status: angenommen

## Entscheidung

Jede Notiz hat eine ganzzahlige `revision`. Schreiben ist Compare-and-Swap auf `baseRevision`. Bei 409 behält der Server seine Fassung, das Gerät zeigt beide an. Kein stilles Last-Write-Wins, kein CRDT.

## Warum

Für eine Person mit zwei Geräten ist das verständlich, und der Server bleibt klein. Striche zusammenzuführen wäre ein eigenes Projekt.

## Nicht

Konflikte nicht automatisch zugunsten der neueren Uhrzeit auflösen. Die Uhr setzt der Server, sie ist kein Merge-Schlüssel.
