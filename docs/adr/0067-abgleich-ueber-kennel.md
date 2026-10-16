# 0067 Abgleich über Kennel statt eigenem Server

Status: angenommen

Ersetzt den eigenen Server aus 0007, 0014, 0039 und 0040. Lokal zuerst (0017), der Tresor (0052) und die Kopplung (0054) bleiben.

## Entscheidung

inkhash gleicht nur noch mit Kennel ab, dem selbst betriebenen Server des Haushalts für alle eigenen Apps. Der Server-Teil von inkhash ist dort das Modul `inkhash` (Kennel ADR 0011). `Server/`, `deploy/`, `compose.yaml` und die Server-Workflows sind aus diesem Repo entfernt; Betrieb, Sicherung und Release des Servers stehen in Kennel.

- Anmelden, Sitzungen, Passwort und Accounts sprechen mit Kennels Kern unter `/v1`.
- Tresor, Kopplung, Workspaces, Änderungen, Notizen und Blobs liegen unter `/v1/apps/inkhash` (`APIClient.appPrefix`).
- Was der Server kann, liest die App aus `modules.inkhash` in `/v1/health`, nicht aus Versionen. Fehlt das Modul, ist der Server kein Kennel oder das Modul aus: Die Adresse gilt als falsch, und eine verbundene App ruht im Zustand `noInkhash`.
- Kennel nimmt keine Klartext-Notizen an. Die App gleicht deshalb erst ab, wenn der Tresor offen ist; das tat sie schon seit 0052.
- Der Vertragstest (`make contract-test`) läuft gegen Kennels Testserver auf PGlite aus einem Kennel-Checkout (`KENNEL_DIR`, sonst `../kennel`). Ohne Checkout wird er mit Warnung übersprungen.

`docs/API.md` bleibt die Beschreibung dessen, worauf sich die App verlässt; Kennel verweist für Tresor, Notizen, Änderungen und Reihenfolge darauf.

## Warum

Dominik betreibt einen Server für alle Apps des Haushalts statt einen pro App. Kennel übernimmt Accounts, Speicher und Verwaltung für alle Module. Zwei Server mit demselben Vertrag zu pflegen, verdoppelt Arbeit und Fehler.

## Nicht

- Keine alten Pfade ohne `/v1/apps/inkhash`, kein Abgleich mit einem alten inkhashd. Bestehende Daten zieht `kenneld import-inkhash` einmal um (Kennel `docs/modules/inkhash.md`).
- Kein zweites Sync-Ziel neben Kennel.
