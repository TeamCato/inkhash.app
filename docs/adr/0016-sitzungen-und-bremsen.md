# 0016 Sitzungen laufen ab, Fehlversuche bremsen

Status: angenommen. Die Mindestlänge des Setup-Tokens und die Einladungen entfallen mit 0021. Vertraute Proxys, die Grenze beim Hashen und IPv6 regelt 0038

Ergänzt 0013.

## Entscheidung

Eine Sitzung endet nach 90 Tagen ohne Benutzung. Der Server schreibt `lastSeenAt` höchstens einmal am Tag. Abgelaufene Sitzungen und Einladungen räumt er beim Start und alle sechs Stunden weg.

Passwörter bleiben PBKDF2-HMAC-SHA256 im selben Format, jetzt mit 600.000 Runden. Ein älterer Hash mit weniger Runden wird beim nächsten erfolgreichen Login ersetzt. Gehasht wird asynchron, damit der Event-Loop frei bleibt.

Neben der Sperre pro Name (acht Fehlversuche, 15 Minuten) zählt der Server Fehlversuche pro Client-Adresse: falsches Passwort, falscher Setup-Token, ungültige Einladung. Nach 30 Fehlversuchen antworten diese Routen der Adresse 15 Minuten lang mit 429. Beide Zähler leben nur im Speicher und sind in der Größe begrenzt.

Lauscht der Server nicht nur auf Loopback, startet er nur mit einem Setup-Token ab 24 Zeichen.

## Warum

Der Setup-Token erzeugt dauerhaft Einladungen und konnte unbegrenzt geraten werden. Synchrones Hashing ließ sich mit wechselnden Namen ohne Sperre zum Stillstand bringen. Sitzungen ohne Ende sind Dauerpasswörter auf verlorenen Geräten.

## Nicht

Hinter einem Reverse-Proxy sieht der Server nur dessen Adresse. Dann teilen sich alle Clients einen Zähler, und ein Angreifer kann neue Logins für 15 Minuten blockieren. Bestehende Sitzungen sind davon nicht betroffen. `X-Forwarded-For` wird bewusst nicht gelesen, bis es eine Einstellung dafür gibt.
