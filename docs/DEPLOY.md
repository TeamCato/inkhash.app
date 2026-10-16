# Server

inkhash hat keinen eigenen Server mehr. Abgeglichen wird über Kennel, den Server des Haushalts, mit dem Modul `inkhash` (ADR 0067).

- Kennel installieren und einrichten: im Kennel-Repo `docs/DEPLOY.md`. Kennel läuft im Heimnetz auf `http://<lan-adresse>:8790`.
- In Kennels Verwaltung (`/admin`) das Modul inkhash einschalten und Accounts anlegen.
- In der App unter Server die Adresse von Kennel eintragen und anmelden. Beim ersten Mal legt die App den Tresor an.

## Umzug von einem alten inkhash-Server

Einmal, in einen Kennel ohne Accounts: `kenneld import-inkhash <datenverzeichnis>`. Accounts, Passwörter, Sitzungen, Tresore, Workspaces und Notizen ziehen mit, Geräte machen ohne Neuanmeldung weiter. Danach in der App die Adresse des Servers auf Kennel ändern. Ablauf im Kennel-Repo, `docs/modules/inkhash.md` und `docs/DEPLOY.md`.
