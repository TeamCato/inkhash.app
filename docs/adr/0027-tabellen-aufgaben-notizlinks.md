# 0027 Tabellen, Aufgaben und Links zu Notizen im Text

Status: angenommen. Aussehen, Ausrichtung, Breiten, Kopfzeile und Zebra geändert durch 0036.

Ergänzt 0004, 0024 (Links im Text) und 0025.

## Entscheidung

**Tabellen sind Markdown-Tabellen.** Gespeichert als `| a | b |` mit Trennzeile `| --- | --- |` nach der ersten Zeile, die die Kopfzeile ist. Im Editor ist jede Tabellenzeile ein Absatz vom Typ `tableRow`; Zellen trennt ein Tabulator. Die Spalten sind gleich breit über die Textbreite, der Layout-Manager zeichnet das Gitter und hinterlegt die Kopfzeile. Zeilen mit weniger Zellen werden beim Schreiben auf die breiteste aufgefüllt. `|` in einer Zelle wird als `\|` geschrieben. Inline-Stile und Links gehen in Zellen.

**So entsteht eine Tabelle.** Eine Zeile wie `| Name | Wert |` und Return macht daraus die Kopfzeile und eine leere Zeile darunter. Das `/`-Menü hat „Tabelle“. Eingefügtes Markdown mit Tabellen wird gelesen. In der Tabelle beendet `|` die Zelle, Tab springt in die nächste (am Ende in eine neue Zeile), Return legt eine Zeile an, Return auf einer leeren Zeile verlässt die Tabelle. Backspace am Zeilenanfang macht die Zeile zu Text.

**Aufgaben.** Kästchen bleiben `- [ ]`/`- [x]` im Markdown. Am Zeilenanfang starten `[ ] `, `[] `, `- [ ] ` und neu `x ` eine Aufgabe.

**Links zu Notizen.** Ein Link auf eine Notiz ist ein Markdown-Link mit dem Ziel `inkhash://note/<id>`, die ID kleingeschrieben. `[[` öffnet ein Menü mit passenden Notizen des Workspace; die Auswahl setzt den Titel als Linktext. Das Linkfeld der Formatleiste schlägt beim Tippen ebenfalls Notizen vor. Ein solcher Link öffnet die Notiz in der App statt im Browser. Zeigt er auf eine Notiz, die es nicht gibt, passiert nichts außer einem Hinweis.

**Pfad.** Das Pfadfeld schlägt beim Fokus die vorhandenen Pfade vor, nach `/` die Ordner der nächsten Ebene.

## Warum

Tabellen und Aufgaben sind das, was Notizen am häufigsten über Fließtext hinaus brauchen. Als Markdown bleiben sie lesbar, wenn die Notiz woanders landet. Ein eigenes URL-Schema für Notizen hält die Links im Markdown und funktioniert in Text und Handschrift gleich (0028).

## Nicht

Keine verbundenen Zellen, keine Spaltenausrichtung, keine Spaltenbreiten von Hand; `:---:` wird gelesen und nicht wiedergegeben. Keine Rückverweise („Wer verlinkt hierher“).
