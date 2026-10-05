# 0001 Dokumentation statt eines zweiten Gehirns

Status: angenommen

## Entscheidung

Agenten lesen `AGENTS.md`, dann `docs/`. Entscheidungen stehen als ADR. Die Karte des Codes heißt `docs/ARCHITECTURE.md`. Fallen stehen in `docs/PITFALLS.md` und verweisen auf einen Test, wo einer möglich ist.

## Warum

Ein Ordner namens `brain` oder eine `sourcemap` neben der Architektur wird eine zweite, veraltete Wahrheit. Agenten vertrauen ihr dann mehr als dem Code. Der Name Sourcemap ist außerdem schon von Compiler-Sourcemaps belegt.

## Nicht

Nicht erst alle Dokumente schreiben und danach erst Code. Die Entscheidung entsteht im selben Schritt wie das Verhalten.
