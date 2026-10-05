# 0036 Tabellen gestalten

Status: angenommen

Ändert 0027 („keine Spaltenausrichtung, keine Spaltenbreiten von Hand“).

## Entscheidung

**Aussehen.** Tabellen haben kein Gitter mehr. Die Kopfzeile ist leicht getönt, ihr Text gedämpft, darunter eine kräftigere Linie. Zwischen den Zeilen liegen Haarlinien, unter der letzten Zeile eine Linie.

**Einstellen.** Steht der Cursor in einer Tabelle, erscheint links am Rand ein Tabellenknopf. Sein Menü stellt die Ausrichtung der Spalte unter dem Cursor (links, Mitte, rechts) ein, macht sie breiter oder schmaler, setzt die Breiten zurück und schaltet Kopfzeile und Zebrastreifen.

**Speichern.** Die Ausrichtung ist Markdown: `---`, `:---:`, `---:` in der Trennzeile. Was Markdown nicht kennt, steht in einer Kommentarzeile direkt nach der letzten Tabellenzeile:

```
<!-- inkhash:table widths=30,70 header=off zebra -->
```

`widths` sind Prozent der Breite je Spalte, `header=off` zeigt die erste Zeile wie jede andere, `zebra` tönt jede zweite Zeile. Unbekannte Wörter werden überlesen. Ohne Einstellung gibt es keine Kommentarzeile. Andere Markdown-Programme blenden sie aus.

**Erste Spalte.** Sie ist immer links ausgerichtet. Im Editor steht vor ihrem Text kein Tabulator, an dem eine Ausrichtung ansetzen könnte; das Menü bietet sie dort nicht an.

## Warum

Das Gitter wirkte wie eine Tabellenkalkulation, nicht wie Papier. Ausrichtung braucht man für Zahlen, Breiten für eine schmale Schlüsselspalte neben langem Text. Die Ausrichtung ist Standard-Markdown; der Rest bleibt in einer Zeile, die die Datei lesbar lässt.

## Nicht

Keine verbundenen Zellen, kein Ziehen an Spaltengrenzen, keine Farben pro Zelle.
