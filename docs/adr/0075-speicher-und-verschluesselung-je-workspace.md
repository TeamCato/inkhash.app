# 0075 Speicher und Verschlüsselung wählt jeder Workspace

Status: angenommen. Punkt 1 geändert durch ADR 0076: der Speicher lässt sich später wechseln. Dominik am 2026-10-20 („Inkhash sollte ebenfalls Storage auswählen können. So kann man z. B.
Notizen auf ein SMB-Share legen. Inkhash sollte außerdem keine Pflicht auf Verschlüsselung haben.“). Setzt teamCato
ADR 0007 und Kennel ADR 0025, 0026 in inkhash um. Ändert ADR 0052 für neue Workspaces: Verschlüsselung ist dort
wählbar, nicht mehr Pflicht. Den Schalter „Verschlüsselt“ (Punkt 1) und Punkt 4 ersetzt ADR 0077: neue Workspaces sind unverschlüsselt.

## Entscheidung

1. **Beim Anlegen eines Workspace auf dem Server** wählt die Person zweierlei, beides gilt für immer:
   - **Verschlüsselt** (Schalter, vorgegeben an): wie bisher nach ADR 0052, mit Tresor. Aus: Die Notizen gehen als
     Klartext hinauf und liegen lesbar als JSON im Speicher, z. B. auf einer SMB-Freigabe; ein Tresor ist dafür nicht
     nötig.
   - **Speicher**: „Standard des Accounts“ oder ein Speicher aus Kennel, den inkhash nutzen darf und der Blobs kann
     (`GET /v1/storages?module=inkhash`). „Neuer Speicher …“ legt einen über KennelKitUI an
     (`KennelNewStorageView`); nur inkhash darf ihn dann nutzen. Für weitere Speicher verweist die App auf Kennels
     Verwaltung.
   Beides bietet die App nur, wenn `/v1/health` `modules.inkhash.plainWorkspaces` und `workspaceStorage` meldet; sonst
   legt sie Workspaces wie bisher an.
2. **Die Verbindung merkt sich die Verschlüsselung:** `WorkspaceLink.sealed`, aus der Antwort des Servers. Bestehende
   Verbindungen und Workspaces von älteren Servern sind verschlüsselt. Ein unverschlüsselter Workspace gleicht mit
   `APIClient` direkt ab, ohne `SealedTransport`, wartet nicht auf einen Tresor und zählt keine Tresor-Epoche.
3. **Die Sitzung gehört inkhash:** Anmelden und Beitreten schicken `module: "inkhash"` (Kennel ADR 0025). Kennel lässt
   die App dann nur Speicher für inkhash freigeben.
4. In der Liste der Server-Workspaces steht bei einem unverschlüsselten „· unverschlüsselt“.

## Warum

Notizen für den Haushalt oder Doku, die auch ohne inkhash lesbar bleiben soll, gehören auf die NAS, ohne Schlüssel.
Private Notizen bleiben verschlüsselt. Der Workspace ist schon die Einheit eines eigenen Abgleichs (ADR 0020), und
Kennel legt Speicher und Verschlüsselung je Workspace fest (Kennel ADR 0026).

## Nicht

- Kein Umschalten der Verschlüsselung und kein Umzug in einen anderen Speicher nach dem Anlegen.
- Aussehen und Bilder der Workspaces gleichen weiter nur mit Tresor ab (ADR 0043, 0052).
- Kein Ändern der Module eines bestehenden Speichers aus der App; das ist Kennels Verwaltung.
