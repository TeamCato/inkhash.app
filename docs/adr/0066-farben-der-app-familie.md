# 0066 Farben und Icon der App-Familie

Status: angenommen. Das Bild des Icons ersetzt 0080.

Ersetzt den Farb-Absatz von 0011. Papier, Haarlinien und Schatten aus 0029 bleiben.

## Entscheidung

inkhash gehört zu einer Familie eigener Apps (teamCato, inkhash, Kennel, Xoot) mit gemeinsamer Palette:

| Rolle | Farbe | `Ink` |
|---|---|---|
| Schrift, aktive Werkzeuge, Hauptknopf | Deep Blue `#0f2138` | `ink` |
| Auswahl, Links, Schlagwörter | Blue Gray `#4e6b7a` | `accent` |
| Was geklappt hat (Verbindung steht) | Sage Green `#7c9a85` | `sage` |
| Was Aufmerksamkeit braucht | Warm Sand `#e9b76d`, als Schrift `#94632a` | `amber`, `warning` |
| Schreibtisch hinter der Bibliothek | Background `#fbf8f1` → Paper Beige, aufgehellt `#f3e6d2` | `deskTop`, `deskBottom` |
| Blatt und Flächen darauf | warmes Weiß `#fdfbf7` | `paper` |

Fehler bleiben rot. Die Farben der Tinte zum Schreiben und die Papierfarben der Notiz (0042) ändern sich nicht.

Das App-Icon ist das gemalte `#` aus Dominiks Designboard (`~/dev/teamCato/Inkhash App-Icon Designboard.png`): Pinselstriche mit Struktur, Spritzer, Papierfaser. Es liegt als Bild in `tools/AppIconArtwork.png` (1024 × 1024, aus dem Blatt geschnitten, Ecken mit Papier aus dem Blatt aufgefüllt). `make icon` legt es nur noch für iOS (volles Quadrat) und macOS (Platte nach Apples Raster) aus. Pinselstruktur und Papier lassen sich im Code nicht treu nachzeichnen; ein Bild ist hier ehrlicher als eine Annäherung.

Die Bildmarke `InkhashMark` in der App und `mark.png` der Website sind dasselbe gemalte `#`, aus `tools/AppIconArtwork.png` geschnitten: `tools/cut-mark.py` (seit 0080 `tools/CutMark.swift`) macht das Papier durchsichtig, Pinselstriche und Spritzer bleiben. Eine nachgezeichnete Vektormarke sah neben dem Icon falsch aus (Dominik, 17.10.2026).

Das Wort steht zweifarbig wie auf dem Blatt: `ink` in Deep Blue, `hash` in ruhigerem Grau (`Ink.wordmark`).

## Warum

Dominik hat für alle Apps ein gemeinsames Icon-Blatt mit dieser Palette entworfen. Kennel, der gemeinsame Server, greift sie ebenfalls auf. inkhash soll daneben nicht wie eine fremde App aussehen.

## Nicht

Kein dunkles Erscheinungsbild. Keine Textur in der Oberfläche; Pinselstruktur und Papierfaser gibt es nur im Icon.
