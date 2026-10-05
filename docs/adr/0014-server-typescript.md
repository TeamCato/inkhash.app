# 0014 Server ist TypeScript auf Node

Status: angenommen

Ersetzt 0007.

## Entscheidung

Der Server ist TypeScript und läuft auf Node. Er benutzt nur die Laufzeit von Node: HTTP, Dateien, Krypto. Kein Framework, kein ORM, keine Suche. Das Dateiformat und die API bleiben die aus ADR 0013 und `docs/API.md`. Passwort-Hashes von einem älteren Python-Prozess bleiben gültig.

## Warum

Python war die kleine Standardbibliothek, als keine andere Laufzeit feststand. Der Betrieb soll eine Sprache sein, die man ohnehin pflegt. Ein Framework würde dieselbe API nur dicker machen.

## Nicht

Kein Express, kein Fastify, keine Datenbank. Der Container bleibt ein Prozess.
