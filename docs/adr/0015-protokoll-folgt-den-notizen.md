# 0015 Das Änderungsprotokoll folgt den Notizdateien

Status: angenommen

Ergänzt 0006.

## Entscheidung

Die Notizdatei ist die Wahrheit, `changes.jsonl` ist ein Verzeichnis darüber. Der Server schreibt erst die Notiz, dann die Zeile im Protokoll. Beim Start liest er das Protokoll einmal, schneidet eine angerissene letzte Zeile ab und vergleicht jede Notizdatei mit ihrem letzten Eintrag. Fehlt einer oder weicht die Revision ab, hängt er einen neuen an. Einträge zu Notizen ohne Datei liefert er nicht mehr aus. Eine kaputte Zeile mitten im Protokoll verhindert den Start.

Der Cursor ist der höchste Wert im Protokoll. `state.json` wird nicht mehr geschrieben. Liegt eine alte Datei noch da, gilt ihr Wert als Untergrenze, damit schon ausgegebene Cursor nicht ein zweites Mal vergeben werden.

`/v1/changes` liefert pro Notiz nur den letzten Eintrag, in Seiten mit `limit` und `hasMore`. Ein Cursor jenseits des Protokolls, etwa nach einem Restore, zählt als 0.

Kommt ein Schreibvorgang mit veralteter `baseRevision`, aber genau dem Inhalt, der schon gespeichert ist, antwortet der Server mit 200 und der gespeicherten Fassung. Das ist der Retry nach einer verlorenen Antwort, kein Konflikt. Für gelöschte Notizen gilt das nicht.

Ein `PUT` mit `baseRevision` > 0 auf eine Notiz, die der Server nicht kennt, ist 404, kein 409. Der Client legt sie dann mit `baseRevision` 0 neu an.

## Warum

Drei Dateien nacheinander zu schreiben ließ nach einem Absturz eine gespeicherte Revision ohne Eintrag zurück. Andere Geräte erfuhren nie davon. Mit nur einer Wahrheit lässt sich der Rest beim Start reparieren. Der Restore aus einer älteren Sicherung ist bei „Sicherung ist Kopieren“ der normale Weg und darf den Abgleich nicht festfahren.

## Nicht

Kein Write-Ahead-Log mit Inhalt, keine Datenbank. Das Protokoll wird weiterhin nicht verdichtet. Inhaltsgleichheit ist kein Merge: verschiedene Inhalte bleiben ein Konflikt.
