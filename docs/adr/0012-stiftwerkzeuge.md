# 0012 Stiftwerkzeuge statt des System-Pickers

Status: angenommen. Teilweise ersetzt durch 0028: Formen, Tape, Fotos und Auswahl gibt es jetzt, Farbe und Stärke sind immer sichtbar, die Leiste ist Papier.

## Entscheidung

Auf dem iPad setzt die Zeichenfläche `canvas.tool` selbst. Die Werkzeuge sind Füller, Stift, Strich, Marker und Radierer, plus Zeichnen mit dem Finger. Ein zweites Tippen auf das aktive Werkzeug öffnet Farbe und Stärke. Die letzte Wahl liegt in den UserDefaults des Geräts, nicht in der Notiz.

Die Knöpfe sind einzelne Glasknöpfe. Eine Glasfläche hinter den Knöpfen schluckt auf iOS 26 die Taps.

## Warum

Der System-Picker von PencilKit ist eine fremde Leiste und kämpft mit mehreren Seiten um den First Responder. Die Spalte folgt dem Muster einer Schreib-App: wenige Tinten, Farbe und Stärke am Werkzeug, sonst nichts auf dem Blatt.

## Nicht

Keine Formen, keine Klebezettel, kein Lasso, keine Fotos. Das bleibt ein Notizblatt. Die Werkzeugwahl wird nicht synchronisiert.
