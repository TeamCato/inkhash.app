# 0045 Workspaces auf dem Server löschen

Status: angenommen

Ändert 0020 („Workspaces werden auf dem Server nicht gelöscht“). Ergänzt 0043 und 0044.

## Entscheidung

**Server.** `DELETE /v1/workspaces/{id}` löscht einen Workspace des Accounts. Er verschwindet aus der Liste und der Reihenfolge, seine Routen antworten danach mit 404. Der Ordner wird nicht vernichtet, sondern nach `deleted/<id>-<zeit>` im Verzeichnis des Accounts verschoben. Zurückholen kann ihn nur der Admin von Hand (DEPLOY.md). `main` lässt sich nicht löschen: Er ist der eigene Bereich des Accounts, und ältere Apps gleichen nur mit ihm ab.

**App.** Die Seite eines angemeldeten Servers listet unter „Workspaces auf dem Server“ alle Workspaces des Accounts, auch die schon auf dem Gerät. Gelöscht wird über das Kontextmenü, auf dem iPad auch durch Wischen, und nur nach einer Warnung. Sie nennt die Zahl der Notizen auf dem Server, gezählt aus dem Änderungsprotokoll, sagt, dass alle Geräte betroffen sind, und welcher Workspace auf diesem Gerät bleibt.

**Was mit den Notizen auf den Geräten passiert.** Ein Workspace, der mit dem gelöschten abgeglichen hat, bleibt auf dem Gerät, mit allen Notizen, und gleicht nicht mehr ab. Auf dem löschenden Gerät gilt das sofort. Andere Geräte merken es beim nächsten Abgleich: `LookSyncer` löst jeden verbundenen Workspace, dessen Server-Workspace in der Liste fehlt, und der Status nennt ihn. Wer die Notizen weiter abgleichen will, verbindet den Workspace danach mit einem anderen Server-Workspace; dort kommt dazu, was schon liegt (0020).

So lassen sich zwei Workspaces zusammenlegen, etwa ein doppeltes „Privat“: den überflüssigen auf dem Server löschen, den Workspace auf dem Gerät mit dem verbliebenen verbinden.

## Warum

Ohne Löschen sammeln sich auf dem Server Workspaces an, die keiner mehr braucht, etwa doppelte nach einer Einrichtung auf mehreren Geräten. Verschieben statt Vernichten macht einen Fehlgriff reparierbar. Die Notizen auf den Geräten zu behalten, statt sie mitzulöschen, verliert auch dann nichts, wenn ein anderes Gerät noch Ungesendetes hatte.

## Nicht

Kein Papierkorb für Workspaces in der App, kein Wiederherstellen aus der App. Kein Löschen von `main`. Kein automatisches Entfernen vom Gerät.
