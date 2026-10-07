# 0043 Workspaces ordnen, eigenes Bild, gleich auf allen Geräten

Status: angenommen

Ergänzt 0020.

## Entscheidung

**Aussehen.** Name, Symbol und ein optionales eigenes Bild bilden das Aussehen eines Workspace. Statt des Symbols kann ein Workspace ein Bild aus Fotos oder Dateien zeigen. Die App schneidet beim Wählen das mittlere Quadrat aus, skaliert es auf 192 × 192 Pixel und speichert es als PNG unter `icons/<sha256>.png` neben `setup.json` (`WorkspaceImage.normalize`, `Workspaces.saveIcon`). `icon` am Workspace ist dieser Hash. Dateien, die kein Workspace mehr nennt, räumt die App weg. Das Symbol bleibt gespeichert und gilt wieder, sobald das Bild weg ist.

**Reihenfolge.** Die Workspaces stehen in der Reihenfolge von `workspaces` in `setup.json`, im Umschalter und in den Einstellungen gleich. Geordnet wird in den Einstellungen durch Ziehen oder im Kontextmenü. Ein neuer Workspace kommt ans Ende.

**Abgleich.** Für verbundene Workspaces ist der Server die Quelle für Aussehen und Reihenfolge. Er speichert pro Workspace `symbol`, `icon` und `updatedAt`, pro Account die Reihenfolge (API.md). Das Bild liegt als gewöhnlicher Blob im Workspace selbst; der Server prüft nur, dass er da ist. Er rendert und prüft nichts darüber hinaus.

Vor den Notizen gleicht `LookSyncer` pro Server ab:

- Wer lokal Name, Symbol oder Bild ändert, setzt `lookPending`. Beim Abgleich schickt das Gerät dann sein Aussehen, sonst übernimmt es das des Servers. Die letzte Änderung gewinnt, Konflikte gibt es nicht.
- Hat auf dem Server noch niemand ein Aussehen gesetzt (`updatedAt` null), schickt das erste Gerät seines. So behalten bestehende Workspaces beim ersten Abgleich, was ein Gerät schon hatte.
- Wer lokal ordnet, merkt den Server in `orderPending` und schickt die Reihenfolge seiner Workspaces dort. Der Server ordnet nur die genannten unter den Plätzen, die sie schon haben; Workspaces, die das Gerät nicht kennt, bleiben stehen. Umgekehrt füllt das Gerät die Plätze seiner verbundenen Workspaces in der Reihenfolge des Servers. Lokale Workspaces und solche anderer Server bleiben, wo sie sind.
- Hat der Account noch keine Reihenfolge (`ordered` falsch), schickt das erste Gerät seine.
- Was sich während des Abgleichs lokal ändert, bleibt; übernommen wird nur, was seit Beginn unverändert ist (`DeviceSetup.adopt`).

Wer einen Workspace mit einem bestehenden Server-Workspace verbindet, übernimmt dessen Aussehen. Server von vor dieser Entscheidung liefern kein `ordered`; dann bleiben Aussehen und Reihenfolge auf dem Gerät.

## Warum

Mit mehr als zwei Workspaces will man die häufigsten oben haben, und zwar auf jedem Gerät an derselben Stelle. Ein Bild erkennt man im Umschalter schneller als eines von zwölf Symbolen. Das Bild als Blob braucht keine neue Art von Ablage auf dem Server. Ohne Revisionen bleibt der Abgleich einfach; ein falsch übernommenes Symbol ist schnell wieder geändert, anders als eine Notiz.

## Nicht

Kein Zuschneiden von Hand, keine Emoji, keine frei wählbaren SF Symbols. Keine Konfliktanzeige für Aussehen oder Reihenfolge. Keine Reihenfolge über Server hinweg.
