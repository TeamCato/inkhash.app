# 0006 Dateien, keine Datenbank

Status: angenommen

## Entscheidung

„Keine Datenbanken“ im Produkt meint keine Tabellen und Ansichten wie in Notion. Der Server benutzt trotzdem kein SQLite. Er schreibt JSON-Notizen, inhaltsadressierte Blobs und ein Änderungsprotokoll in ein Verzeichnis.

## Warum

Sicherung ist das Kopieren dieses Verzeichnisses. Ein eingebettetes Datenbankformat wäre für diesen Umfang mehr Maschinerie als Nutzen.

## Nicht

Das Protokoll wächst mit jeder Änderung und wird nicht verdichtet. Das ist akzeptiert, bis es weh tut. Dann eine neue ADR, nicht still SQLite einführen.
