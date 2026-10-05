# 0004 Text ist kanonisches Markdown

Status: angenommen. Tabellen ergänzt durch 0027, Links durch 0024.

## Entscheidung

Gespeichert wird Markdown. Der Editor zeigt die Formatierung. Block-Syntax (`# `, Listen, Aufgaben, Zäune) wird beim Tippen verbraucht. `**`, `*` und Backticks werden zu fett, kursiv und Code, sobald das Paar geschlossen ist. `[Text](Ziel)` wird zum Link, siehe 0024.

## Warum

Die Datei bleibt lesbar, diffbar und unabhängig von einem Attributed-String. Die Oberfläche bleibt trotzdem frei von Rohsyntax.

## Nicht

`# Titel` mit Leerzeichen ist eine Überschrift, kein Tag. Tabellen, Bilder und Einbettungen gehören nicht zur Teilmenge. Was der Parser nicht kennt, bleibt ein Absatz.
