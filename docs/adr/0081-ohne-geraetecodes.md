# 0081 Ohne Gerätecodes, Kennel-Adresse aus Bonjour

Status: angenommen. Dominik am 2026-10-23. Ersetzt den Teil „Weiteres Gerät verbinden …“ aus 0074.

## Kontext
Kennel hat Gerätecodes für bestehende Accounts abgeschafft (Kennel ADR 0036): Wer schon einen Account hat, meldet sich
mit Name und Passwort an, Codes gibt es nur noch als Einladung für neue Personen. KennelKit kennt seitdem weder
`JoinCodeKind.device` noch `KennelDeviceCodeView`, und inkhash baute mit dem aktuellen KennelKit nicht mehr. Dazu nennt
Kennel per Bonjour jetzt seine Adresse hinter dem Proxy (Kennel ADR 0046), die `KennelDiscovery` statt der IP nimmt.

## Entscheidung
- „Weiteres Gerät verbinden …“ fällt weg: `DeviceCodeView`, `ServerSessions.issueDeviceCode`/`revokeDeviceCode` und
  die Vertragstests für Gerätecodes. Weitere Geräte melden sich mit Name und Passwort an.
- Der Depot-Lauf löst `kennel` bei jedem Build frisch auf, auch für `InkhashCore` (wie `ci.yml`), damit kein alter
  Paketstand auf dem Build-Mac ein altes KennelKit festhält.

## Folgen
Gefundene Kennels landen mit ihrer öffentlichen Adresse im Feld, wenn sie dort antworten (z. B.
`https://kennel.home.kriminik.de`), sonst wie bisher mit der IP.
