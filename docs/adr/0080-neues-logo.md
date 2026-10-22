# 0080 Neues Logo: das gerade gemalte #

Status: angenommen. Dominik am 2026-10-22. Ersetzt das Bild des App-Icons aus 0066; Palette und Aufbau von 0066 bleiben.

## Kontext
Das bisherige Icon war ein schräges `#` aus vier Strichen, der linke senkrechte heller und dahinter. Dominik hat ein
neues Logo gemalt (teamCato `brand/inkhash/inkhash-logo.png`).

## Entscheidung
**Das Logo ist ein gerade stehendes `#` aus vier gleich dunklen Pinselstrichen** mit Spritzern, auf hellem Papier, in
zwei Ecken tiefblaue Tusche. Es ist zugleich das App-Icon: `tools/AppIconArtwork.png` ist das Logo auf 1024 × 1024,
`make icon` legt es wie bisher für iOS und macOS aus. Eine Kopie liegt in `docs/assets/inkhash-logo.png`.

**Die Bildmarke** (`InkhashMark`, `Website/mark.png`) ist dasselbe `#` ohne Papier und ohne die blauen Ecken.
`tools/CutMark.swift` schneidet sie aus dem Icon und blendet alles außerhalb eines Kreises um die Mitte aus. Das
Werkzeug ersetzt `tools/cut-mark.py`, damit `make icon` ohne Python und Pillow läuft.

## Nicht
Kein Nachzeichnen als Vektor; Pinsel und Papier bleiben Bild (0066).
