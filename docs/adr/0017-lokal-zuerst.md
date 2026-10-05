# 0017 Lokal zuerst, der Server ist ein Plus

Status: angenommen, erweitert durch 0020 (eine Bibliothek pro Workspace)

Ersetzt 0009 für das Gerät. Der Server bleibt, wie 0013 und 0015 ihn beschreiben.

## Entscheidung

Jedes Gerät hat genau eine Bibliothek. Sie gehört keinem Account und funktioniert ohne Server, ohne Anmeldung und ohne Netz vollständig: Schreiben, Zeichnen, Erkennen, Suchen, Löschen.

Ein Server ist optional. Die Bibliothek merkt sich, mit welchem Account sie zuletzt abgeglichen hat (`account.txt`).

- **Anmelden am selben Account** setzt den Abgleich fort, mit Cursor und Revisionen.
- **Anmelden an einem anderen Account oder zum ersten Mal**: Die Bibliothek löst sich vom alten Account. Jede Notiz bekommt Revision 0 und gilt als geändert, Grabsteine verschwinden, der Cursor geht auf 0. Eine liegengebliebene Server-Fassung aus einem Konflikt wird eine eigene Notiz. Danach lädt der Abgleich alles in den neuen Account und holt dessen Notizen dazu.
- **Abmelden** beendet nur den Abgleich. Die Notizen bleiben sichtbar und bearbeitbar.
- **Abgelaufene Sitzung**: Antwortet der Server auf eine Anfrage mit Sitzung mit 401, meldet sich die App selbst ab, ohne den Server zu fragen. Die Bindung bleibt, der Name wird für die nächste Anmeldung vorgeschlagen, und die Bibliothek zeigt einen Hinweis, bis man sich anmeldet oder ihn wegklickt. Ein 401 auf eine Anfrage, die noch mit einer älteren Sitzung lief, beendet die aktuelle nicht.

Ältere Geräte hatten einen Speicher pro Account und einen für „abgemeldet“. Beim ersten Start wird der Speicher des angemeldeten Accounts zur Bibliothek, und abgemeldete Notizen kommen als neue lokale Notizen dazu. Speicher anderer Accounts bleiben unberührt liegen, damit nichts ungefragt in einen fremden Account wandert.

## Warum

Eine Notiz-App, die ohne eigenen Server nicht taugt, schließt alle aus, die keinen betreiben wollen. Abgleich ist ein Plus, keine Voraussetzung. Eine einzige Bibliothek ist einfacher zu verstehen als ein Speicher pro Account, der beim Abmelden verschwindet.

## Nicht

Weiterhin kein iCloud und kein zweites Sync-Ziel. Eine Bibliothek gleicht höchstens mit einem Account ab. Kein Zusammenführen von Inhalten: kehrt man zu einem früheren Account zurück, löst der Server gleiche Inhalte still auf (ADR 0015), verschiedene werden Konflikte mit beiden Fassungen.
