# 0088 Neues Logo: das blaue Pinsel-# auf der Papierplatte

Status: angenommen. Dominik am 2026-10-28. Ersetzt das Bild aus 0080; Aufbau aus 0066 und 0080 bleibt.

## Kontext
Dominik hat das Logo neu gemalt (teamCato `brand/inkhash/inkhash-logo.png`): ein gerade stehendes `#` aus breiten,
tiefblauen Pinselstrichen mit Spritzern, auf einer cremefarbenen Papierplatte mit runden Ecken. Die tiefblauen
Tuscheecken aus 0080 gibt es nicht mehr.

## Entscheidung
- `tools/AppIconArtwork.png` ist das neue Logo ohne Platte: das Papier mit dem `#` als randloses Quadrat 1024 × 1024.
  Die runden Ecken und der Rand der Platte kommen wie bisher aus `make icon` (iOS rundet selbst, der Mac bekommt die
  Platte auf Apples Raster).
- `docs/assets/inkhash-logo.png` ist eine verkleinerte Kopie des Logos mit Platte.
- Die Bildmarke (`InkhashMark`, `Website/mark.png`) bleibt das ausgeschnittene `#`. Weil die Querstriche fast bis an
  den Rand reichen und keine blauen Ecken mehr ausgeblendet werden müssen, behält `tools/CutMark.swift` einen
  größeren Kreis (0,48 statt 0,44 der Seite).

## Nicht
Kein Nachzeichnen als Vektor; Pinsel und Papier bleiben Bild (0066).
