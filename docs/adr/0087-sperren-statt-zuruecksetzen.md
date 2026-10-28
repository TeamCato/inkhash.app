# 0087 Sperren statt Schlüssel zurücksetzen

Status: angenommen, umgesetzt. Dominik am 2026-10-28. Setzt teamCato ADR 0016 und Kennel ADR 0067 um. Ändert ADR 0052
und 0082, soweit sie das Zurücksetzen nennen.

## Entscheidung

- Einstellungen › Kennel › Verschlüsselung zeigt freigeschaltet „Sperren …“ statt „Zurücksetzen …“. Nach einer
  Rückfrage vergisst dieses Gerät den Schlüssel, auch einen, den ein älteres inkhash selbst aufbewahrt hat
  (`vault-<server>`). Kennel und andere Geräte bleiben, wie sie sind. Wieder freischalten wie auf einem neuen Gerät.
- „Freischalten“ hat kein „Wiederherstellungsschlüssel nicht mehr da?“ mehr; `APIClient.resetVault` ist weg.
- `epoch` bleibt im Vertrag und in der Bindung der Bibliotheken, zählt aber nicht mehr hoch.

## Warum

Ein neuer Schlüssel machte keinen verschlüsselten Workspace wieder lesbar; Zurücksetzen hat nur zerstört (teamCato ADR
0016).

## Grenze

Sperren nimmt dem Gerät den Schlüssel für den Abgleich. Notizen, die schon auf dem Gerät liegen, bleiben dort lesbar.
