# 0089 Endgültig löschen wird abgeglichen

Status: angenommen. Dominik am 2026-10-29. Ändert den Papierkorb aus 0020.

## Kontext
Nach 0020 wanderte „In den Papierkorb“ über Kennel auf jedes Gerät, „Endgültig löschen“ und „Papierkorb leeren“ aber
nicht: sie entfernten die Notiz nur vom eigenen Gerät. Kennel behielt den Grabstein samt Inhalt, und Dominik musste den
Papierkorb auf jedem Gerät einzeln leeren.

## Entscheidung
- Eine Notiz trägt `purgedAt`, wenn sie endgültig gelöscht ist. Endgültig löschen macht aus ihr einen geleerten
  Grabstein: `deletedAt` und `purgedAt` gesetzt, Titel, Text, Abschrift, Schlagwörter, Seiten, Ordner, Favorit und
  Papier leer. Er verschwindet sofort aus dem Papierkorb und geht beim nächsten Abgleich als gewöhnliches `PUT` mit
  `deleted: true` hoch (versiegelt wie jede Notiz). Kennel ersetzt damit den alten Inhalt und löscht ihn im Speicher.
  Danach entfernt das Gerät die Notiz.
- Holt ein Gerät eine Notiz mit `purgedAt`, entfernt es sie, auch aus dem Papierkorb. Hat es sie inzwischen
  wiederhergestellt oder bearbeitet und noch nicht abgeglichen, gewinnt seine Fassung: sie geht auf der Revision des
  Grabsteins wieder hoch.
- Antwortet Kennel beim Hochladen mit einem Konflikt und die Notiz lebt dort wieder, gewinnt das Wiederherstellen auf
  dem anderen Gerät, die Notiz kommt zurück. Liegt sie dort nur im Papierkorb, geht der geleerte Grabstein einmal auf
  Kennels Revision hoch.
- Ohne Abgleich und für Notizen, die Kennel nie gesehen hat, bleibt es wie bisher: sie gehen sofort vom Gerät.
- Kennel braucht dafür nichts Neues: Er kann versiegelte Notizen nicht lesen, er speichert den Grabstein wie jede
  andere Fassung. Eine ältere App sieht ihn als leere Notiz im Papierkorb.

## Nicht
Die Zeile des Grabsteins bleibt in Kennel, damit Geräte, die lange nicht abgeglichen haben, davon erfahren. Bilder der
Notiz (Blobs) räumt Kennel weiterhin nicht auf; dafür gibt es keine Speicherbereinigung.
