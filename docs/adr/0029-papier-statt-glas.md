# 0029 Papier statt Glas

Status: angenommen

Ersetzt den Glas-Teil von 0011. Hell, Anthrazit und ein ruhiges Blau bleiben.

## Entscheidung

Was über dem Blatt liegt, ist ebenfalls Papier: deckend `Ink.paper`, eine weiße Haarlinie, ein weicher Schatten, durchgehende Rundung. Das gilt für Suche, Schlagwort-Kapseln, `/`-Menü, Formatleiste, Konflikt-Banner, Werkzeugleiste und Knöpfe. Ein Knopf ist Papier mit Haarlinie; der aktive oder wichtigste ist Anthrazit mit Papierschrift, wie `.button.primary` auf der Website. Kein `glassEffect`, kein Material.

Maße wie auf der Website: Blatt 22 Rundung und Schatten 0/12/40 bei 7 %, Leisten 18 und 0/8/24 bei 5 %, Knöpfe 14 und 0/4/16 bei 5 %. Die Helfer in `Theme.swift` bleiben die einzige Stelle dafür.

## Warum

Glas machte die Oberfläche unruhig und hing an Systemversionen (Glas schluckt unter iOS 26 Taps, siehe `inkGlassChrome`). Papier passt zur Marke und zur Website, und es sieht auf iOS 17 wie auf 27 gleich aus.

## Nicht

Kein dunkles Erscheinungsbild, keine Texturen.
