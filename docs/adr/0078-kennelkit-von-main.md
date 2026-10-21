# 0078 KennelKit kommt bis zum Public Release von `main`

Status: angenommen. Dominik am 2026-10-21. Ändert Punkt 1 von ADR 0073. Folgt Kennel ADR 0029.

## Kontext
Kennel legt bis zum ersten Public Release keine Tags, Releases oder Images mehr an und hat die bisherigen gelöscht
(Kennel ADR 0029); intern läuft alles über Depot. inkhash band KennelKit mit `.upToNextMinor(from: "0.8.0")` an diese
Tags.

## Entscheidung
`Packages/InkhashCore/Package.swift` und `project.yml` binden KennelKit mit `branch: "main"` von
`https://github.com/teamcato/kennel` ein. `KENNELKIT_DIR` bleibt wie in ADR 0073.

## Konsequenzen
- Ein neuer Stand von KennelKit kommt mit `swift package update kennel` (bzw. „Update to Latest Package Versions“ in
  Xcode), nicht mit einem neuen Tag.
- `Package.resolved` liegt nicht im Repo; jeder frische Checkout und die CI nehmen den aktuellen `main` von Kennel. Ein
  Bruch dort trifft inkhash beim nächsten Bauen.
- Beim ersten Public Release kehrt inkhash zu einer Version zurück (neue ADR).

## Verworfene Alternativen
- Auf einen festen Commit (`revision:`) pinnen: jedes Update wäre eine Änderung an zwei Dateien; bis zum Public Release
  lohnt das nicht.
