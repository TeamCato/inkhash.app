# 0025 Ein Textfeld pro Notiz

Status: angenommen

Ändert 0018 (Text) und 0023. Das Speicherformat aus 0004 bleibt.

## Entscheidung

**Eine Textnotiz ist ein einziges Textfeld.** Absätze, Überschriften, Listen, Aufgaben und Code liegen im selben `NSTextView` (Mac) beziehungsweise `UITextView` (iPad). Pfeiltasten, Markieren, Löschen und Einfügen gehen über Absatzgrenzen wie in jedem Texteditor. Backspace am Anfang eines Absatzes hängt ihn an den vorigen an, auch an eine Überschrift.

**Der Blocktyp ist ein Absatzattribut.** Jeder Absatz trägt `inkhash.blockType`, bei Aufgaben `inkhash.checked`, bei Code `inkhash.language`, auf allen Zeichen einschließlich seines Zeilenumbruchs. Nach jeder Eingabe gilt für den ganzen Absatz der Typ seines ersten Zeichens; so übernimmt ein angehängter Absatz den Typ des vorigen. Ein Code-Block ist eine Folge von Code-Absätzen. Der leere letzte Absatz hat kein Zeichen; sein Typ steht im Editor (`trailing`) und in den Tippattributen.

**Markdown bleibt die Wahrheit.** Beim Öffnen wird das Markdown in Absätze übersetzt, nach jeder Änderung zurück in Blöcke und Markdown (`NoteDocument`). Öffnen schreibt nichts.

**Marker zeichnet der Layout-Manager.** Aufzählungspunkt, Nummer und Kästchen stehen im linken Einzug jedes Absatzes, gezeichnet von `MarkerLayoutManager`. Ein Klick oder Tipp auf das Kästchen hakt ab. Der Text aller Absätze beginnt am selben Einzug wie Titel und Pfad.

**Eingabe-Regeln.** Return fügt das Textfeld selbst ein, der Editor setzt danach die Stile (P-038). Return in einer Liste setzt die Liste fort, in einem leeren Listenpunkt beendet es sie. Return in einer Überschrift beginnt einen normalen Absatz. Backspace am Anfang eines Listenpunkts, einer Überschrift oder einer Code-Zeile macht daraus zuerst normalen Text. Block-Kürzel (`# `, `- `, `[ ] `, `1. `, ```` ``` ````) wirken am Anfang eines normalen Absatzes. Mehrzeiliges Einfügen wird als Markdown gelesen; formatierter Text aus anderen Apps kommt als reiner Text.

**Formatleiste und `/`-Menü** hängen an der Auswahl beziehungsweise am Cursor im einen Textfeld. Die Blocktyp-Auswahl der Leiste gilt für alle markierten Absätze.

## Warum

Ein Textfeld je Block machte aus einer Notiz eine Liste von Feldern. Nach oben, nach unten, Backspace und Löschen mussten pro Grenze nachgebaut werden, über zwei Absätze markieren ging gar nicht, und jede Lücke fühlte sich an wie ein Formular statt wie ein Text. Ein Markdown-Dokument ist Fließtext; das Bearbeiten soll es auch sein.

## Nicht

Kein TextKit 2: Die Marker brauchen `NSLayoutManager.drawBackground`, das gibt es auf beiden Systemen nur in TextKit 1. Keine verschachtelten Listen und kein Einrücken mit Tab. Zwei direkt aufeinanderfolgende Code-Blöcke werden zu einem.
