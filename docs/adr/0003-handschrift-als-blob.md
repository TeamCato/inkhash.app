# 0003 Handschrift als PKDrawing-Blob

Status: angenommen

## Entscheidung

Eine Seite ist `PKDrawing.dataRepresentation()`, inhaltadressiert mit SHA-256. Der Server speichert die Bytes und liest sie nicht.

## Warum

Beide Geräte sind Apple-Geräte. Eine eigene Strich-Struktur bräuchte man für ein Zusammenführen einzelner Striche oder für Clients außerhalb von Apple. Beides ist nicht Ziel.

## Nicht

macOS bietet in diesem SDK `PKDrawing`, aber kein `PKCanvasView`. Der Mac zeigt die Seite als Bild. Gezeichnet wird auf dem iPad. Die Zeichenfläche dort nicht bei jedem SwiftUI-Update neu setzen, siehe P-012.
