# 0083 „In Kennel löschen“ räumt den Speicher, mit eigener Rückfrage

Status: angenommen. Dominik am 2026-10-24 („In inkhash ‚von Kennel löschen‘ bei einem Workspace lässt die Daten auf
dem Speicher liegen“; beheben, mit klarer Rückfrage vorher, eigener Dialog statt Systemdialog). Gegenstück zu Kennel
ADR 0063. Ergänzt ADR 0045 und ADR 0077 Punkt 6 („In Kennel löschen …“).

## Kontext

„In Kennel löschen …“ fragte in einem Systemdialog und versprach: „Rückgängig machen kann das nur ein Admin in
Kennel.“ Kennel setzte dafür nur `deleted_at`; Notizen und Bilder blieben im Speicher liegen, ohne dass sie je jemand
zurückholte oder aufräumte.

## Entscheidung

1. **Kennel räumt auf.** Meldet `/v1/health` `modules.inkhash.workspacePurge: true`, löscht Kennel die Notizen und
   Bilder des Workspace im Speicher (Kennel ADR 0063). Die App ändert am Ablauf von ADR 0045 nichts: Der Workspace
   verschwindet in Kennel für alle Geräte, hier und auf den anderen Geräten bleibt er ohne Abgleich.
2. **Eigene Rückfrage.** „In Kennel löschen …“ öffnet `KennelDeleteSheet` im Stil der App, kein Systemdialog. Er
   nennt, was wo passiert: im Speicher (mit Namen und, wenn Kennel sie liefert, der Zahl der Notizen) wird gelöscht,
   auf den anderen Geräten endet der Abgleich, hier bleiben die Notizen. Darunter steht „Das lässt sich nicht
   rückgängig machen.“, die Schaltfläche heißt „Endgültig löschen“, „Abbrechen“ liegt daneben und auf Escape.
   Während Kennel löscht, lässt sich der Dialog nicht wegwischen; ein Fehler steht im Dialog.
3. **Ältere Kennel.** Ohne `workspacePurge` bleibt der Text ehrlich: Die Daten bleiben im Speicher liegen, zurückholen
   kann sie nur ein Admin, die Schaltfläche heißt weiter „In Kennel löschen“.

## Folgen

- Neues Feld `ModuleInfo.workspacePurge`; der Vertragstest prüft es.
- „Nur noch auf diesem Gerät …“ und „Vom Gerät entfernen“ fragen weiter im Systemdialog; sie löschen nichts in Kennel.
