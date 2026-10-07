# 0020 Workspaces, Ordner, Favoriten und Papierkorb

Status: angenommen

Erweitert 0017. Die Seitenleiste ändert 0022; Heute entfällt dort. Eine Bibliothek pro Gerät wird eine Bibliothek pro Workspace.

## Entscheidung

**Server und Workspaces sind getrennt.** Ein Gerät kennt beliebig viele Server, jeden mit höchstens einem angemeldeten Account (`setup.json`, die Sitzung liegt pro Server in der Keychain). Ein Workspace ist eine eigene lokale Bibliothek unter `workspaces/<id>/` mit eigenen Notizen, Ordnern, Schlagwörtern und eigener Suche. Er bleibt nur auf dem Gerät oder gleicht mit genau einem Workspace eines Accounts auf einem der Server ab (`WorkspaceLink`). Ein Account kann mehrere Workspaces abgleichen, verschiedene Workspaces eines Geräts können auf verschiedenen Servern liegen.

**Auf dem Server** hat jeder Account den Workspace `main`, sein bisheriges Ablageverzeichnis. Weitere liegen unter `workspaces/<uuid>/` im Account, mit eigenem Änderungsprotokoll. Die Notizrouten gibt es unter `/v1/workspaces/{ws}/…`, für `main` weiterhin ohne Präfix. Ältere Apps gleichen so unverändert mit `main` ab.

**Bindung.** `Library.bind` bekommt pro Workspace den Schlüssel aus Account und Server-Workspace. Für `main` ist es die nackte Account-ID wie bisher, damit eine alte Bibliothek ohne erneutes Hochladen weiterläuft. Zeigt ein Workspace auf ein anderes Ziel, gilt 0017: alles wird dort neu hochgeladen.

**Migration.** Die eine Bibliothek wird der Workspace „Privat“. War sie angemeldet, wird aus Adresse und Account der erste Server, und „Privat“ gleicht mit dessen `main` ab. `setup.json` wird vor dem Verschieben geschrieben; ein Abbruch dazwischen wird beim nächsten Start nachgeholt.

**Ordner** sind ein Pfad an der Notiz (`folder`, Segmente mit `/`, leer heißt kein Ordner). Eine Notiz liegt in genau einem Ordner, Schlagwörter gehen quer darüber. Leere Ordner merkt sich nur das Gerät (`folders.json` im Workspace). Umbenennen schreibt den Pfad in jede betroffene Notiz, Entfernen hebt die Notizen eine Ebene nach oben.

**Favorit** ist `favorite` an der Notiz und wird abgeglichen.

**Papierkorb** zeigt die Grabsteine (`deletedAt`). Löschen legt jede Notiz dort ab, auch eine, die nie den Server gesehen hat; die bleibt dann nur lokal liegen. Wiederherstellen setzt `deletedAt` zurück und schickt die Notiz mit ihrer Revision, der Server holt sie damit zurück. Endgültig löschen entfernt sie nur vom Gerät und erst, wenn ihr Löschen abgeglichen ist.

**Heute** zeigt Notizen, deren `updatedAt` auf den heutigen Tag fällt.

## Warum

Privat und Arbeit sollen sich nicht mischen, auch nicht in Suche und Schlagwörtern. Einen eigenen Server pro Workspace zu verlangen wäre zu viel, ihn auszuschließen zu wenig. Ordner als Pfad an der Notiz brauchen keine zweite Art von Objekt im Abgleich.

## Nicht

Kein Teilen eines Workspace zwischen Accounts (0013 bleibt). Keine leeren Ordner auf dem Server. Kein Verschieben einer Notiz zwischen Workspaces. Workspaces werden auf dem Server nicht gelöscht, nur vom Gerät entfernt (geändert durch 0045: Löschen auf dem Server, solange einer bleibt).
