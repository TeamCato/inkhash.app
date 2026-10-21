# 0076 Ein Workspace zieht auf dem Server in einen anderen Speicher um

Status: angenommen. Dominik am 2026-10-21 („Wäre es möglich, auch einen Move von z. B. inkhash-Notizen in einen anderen
Storage auf Kennel zu supporten?“). Setzt Kennel ADR 0027 um. Ändert ADR 0075 Punkt 1: der Speicher gilt nicht mehr
für immer, die Verschlüsselung schon.

## Entscheidung

1. Im Fenster eines verbundenen Workspace steht unter „Speicher auf dem Server“, wo er liegt, eine Auswahl der Speicher,
   die inkhash nutzen darf (dazu „Standard des Accounts“), „Umziehen“ und „Neuer Speicher …“. Nur wenn `/v1/health`
   `modules.inkhash.workspaceMove` meldet.
2. „Umziehen“ ruft `PUT /v1/apps/inkhash/workspaces/{id}/storage`. Kennel zieht im Hintergrund um; das Fenster fragt
   alle zwei Sekunden nach, bis der Umzug vorbei ist, und gleicht dann ab. Ein gescheiterter Umzug steht mit Grund im
   Fenster; die Notizen liegen dann noch am alten Ort.
3. Während des Umzugs antwortet Kennel beim Schreiben 423. Die Statuszeile sagt „Der Workspace zieht auf dem Server
   gerade um“, und der nächste Abgleich holt nach, was liegen blieb. Auf dem Gerät ändert sich nichts.

## Warum

Der Server hat alle Inhalte schon und zieht sie um, ohne dass ein Gerät etwas neu hochlädt; die App muss nur sagen,
wohin, und zeigen, wann es vorbei ist.

## Nicht

- Kein Umschalten der Verschlüsselung beim Umzug.
- Keine Fortschrittsanzeige in Prozent.
