# 0044 Workspaces vom Server übernehmen

Status: angenommen

Ergänzt 0020 und 0043.

## Entscheidung

Die Seite eines angemeldeten Servers zeigt unter „Auf dem Server“ jeden Workspace des Accounts, mit dem auf diesem Gerät noch kein Workspace abgleicht (`DeviceSetup.unlinked`). Jeder lässt sich einzeln hinzufügen, mehrere auf einmal mit „Alle hinzufügen“. Nach dem Anmelden an einem neuen Server folgt diese Seite direkt, statt zurück zur Liste zu gehen.

Hinzufügen legt pro Server-Workspace einen Workspace auf dem Gerät an, verbunden mit ihm, mit Name und Symbol vom Server (`DeviceSetup.addLinked`), und gleicht sofort ab. Bild und Platz in der Reihenfolge kommen mit dem Abgleich nach 0043, die Notizen mit dem Abgleich der Bibliothek.

Hat das Gerät nur einen Workspace, der nicht verbunden ist und weder Notizen noch Ordner hat, übernimmt dieser den ersten hinzugefügten. Das ist der Fall nach einer neuen Installation: sonst bliebe dort ein leeres „Privat“ neben dem vom Server stehen.

## Warum

Wer die App neu installiert oder ein zweites Gerät einrichtet, will die Workspaces haben, die es schon gibt, nicht jeden von Hand anlegen und verbinden. Eine Auswahl statt eines automatischen Übernehmens lässt Workspaces weg, die auf diesem Gerät nicht gebraucht werden.

## Nicht

Kein automatisches Hinzufügen neuer Server-Workspaces bei späteren Abgleichen. Kein Löschen von Workspaces auf dem Server (0020 bleibt).
