# 0046 Accounts verwalten

Status: angenommen

Ändert 0021 („Kein Passwort ändern, kein Account löschen, kein zweiter Admin“).

## Entscheidung

Auf `/admin` kann ein Admin jeden Account bearbeiten, auch den eigenen:

- **Umbenennen.** Der neue Name gilt ab dem nächsten Anmelden; laufende Sitzungen bleiben gültig, weil sie an der Account-ID hängen. Ein vergebener Name ist 409 `name-taken`.
- **Neues Passwort setzen.** Alle Sitzungen des Accounts enden, außer der, mit der der Admin gerade arbeitet. Die Geräte des Accounts zeigen „Anmeldung abgelaufen“ und melden sich mit dem neuen Passwort an.
- **Zum Admin machen oder Admin-Rechte entziehen.** Es kann mehrere Admins geben. Der letzte Admin bleibt Admin: 400 `last admin`.
- **Löschen**, nach einer Rückfrage. Die Identität und alle Sitzungen verschwinden sofort; der Name ist danach frei. Die Daten des Accounts werden nicht vernichtet, sondern mit der Identität nach `deleted-accounts/<id>-<zeit>` verschoben; zurückholen kann sie nur, wer Zugriff auf den Server hat (DEPLOY.md). Den letzten Admin zu löschen ist 400 `last admin`. Löscht ein Admin sich selbst, endet seine Sitzung mit.

Die Geräte eines gelöschten Accounts bekommen beim nächsten Abgleich 401 und behalten ihre Notizen, wie bei einer abgelaufenen Sitzung (0016, 0017).

`GET /v1/accounts` nennt zusätzlich `me`, die ID des fragenden Accounts, damit die Seite den eigenen Account kennzeichnen kann.

## Warum

Ein selbst betriebener Server mit wenigen Personen braucht die üblichen Handgriffe, ohne dass jemand im Datenverzeichnis Dateien bearbeitet: ein vergessenes Passwort neu setzen, einen Tippfehler im Namen korrigieren, eine Person, die geht, entfernen, die Verwaltung teilen. Verschieben statt Vernichten macht einen Fehlgriff reparierbar.

## Nicht

Kein Ändern des eigenen Passworts in der App. Keine E-Mail, keine Selbstregistrierung (0021 bleibt). Kein Wiederherstellen gelöschter Accounts über die Seite.
