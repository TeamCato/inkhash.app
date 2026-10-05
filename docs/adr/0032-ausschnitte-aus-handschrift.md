# 0032 Ausschnitte aus Handschrift im Text

Status: angenommen. `/Ausschnitt`, neue Handschrift aus dem Text und Text-Ausschnitte auf der Seite durch 0035. Ergänzt 0004 (Markdown), 0027 (Links zu Notizen) und 0028 (Auswahl auf der Seite). 0002 bleibt: Die Textnotiz enthält keine Striche, nur einen Verweis.

## Entscheidung

**Ein Ausschnitt ist ein Fenster, keine Kopie.** Eine Textnotiz kann einen rechteckigen Bereich einer Handschriftseite zeigen. Gespeichert wird nur der Verweis; gezeichnet wird beim Anzeigen aus der Quellnotiz. Ändert sich die Handschrift im Bereich, zeigt der Ausschnitt den neuen Stand.

**Speicherform.** Ein Ausschnitt ist ein eigener Absatz aus genau einem Markdown-Bild:

```
![Skizze Lager](inkhash://note/<noteID>/page/<pageID>?rect=<x>,<y>,<w>,<h>)
```

IDs kleingeschrieben, das Rechteck in Seitenkoordinaten wie die Striche (0018), Zahlen mit Punkt und höchstens zwei Nachkommastellen. Die `pageID` ist die UUID der Seite, deshalb übersteht der Verweis das Umsortieren von Seiten. Das Label ist frei, aber nie leer: Ohne Eingabe heißt es „Ausschnitt“. Ältere Versionen lesen `![](…)` als Text und würden die Klammer beim Speichern escapen. Andere Bilder (`![…](https://…)`) bleiben Text wie bisher, ebenso ein Ausschnitt mitten in einem Absatz. Im Code heißt der Absatztyp `excerpt`, in der Oberfläche „Ausschnitt“.

**Darstellung.** Der Ausschnitt steht ohne Rahmen auf dem Blatt, links eine feine Akzentlinie, darunter in kleiner Schrift das Label. Er ist höchstens so breit wie der Text und höchstens so groß wie im Original. Er zeigt Tinte und Elemente (Bilder, Formen, Tape) der Quelle. Gerendert wird mit `PKDrawing.image(from:scale:)` und `ElementRenderer`; das geht auch auf dem Mac. Ein Tipp (Mac: Klick) öffnet die Quellnotiz an dieser Stelle. Backspace hinter dem Ausschnitt löscht ihn als Ganzes.

**Platzhalter.** Gibt es die Notiz oder Seite im Workspace nicht, liegt sie im Papierkorb oder ist sie noch nicht abgeglichen, steht an der Stelle ein Kasten mit dem Label und dem Grund. Ragt das Rechteck über eine kleiner gewordene Seite hinaus, wird es auf die Seite beschnitten.

**Nur im Workspace.** Ausschnitte zeigen nur auf Notizen desselben Workspace. Ein Verweis in einen anderen Workspace, etwa durch Einfügen, ist ein Platzhalter.

**Entstehen, zwei Wege.**
- Auf der Handschriftseite hat die Auswahl (0028) „Als Ausschnitt kopieren“. Das Rechteck ist die Begrenzung der Auswahl plus etwas Rand. In die Zwischenablage kommt der Verweis; Einfügen in eine Textnotiz macht daraus einen Ausschnitt, als reiner Text ist er die Markdown-Zeile oben.
- Im Text hat das `/`-Menü „Ausschnitt“. Es fragt wie `/Link` nach einer Notiz (nur Handschrift), zeigt sie in einem Fenster, und man zieht dort das Rechteck auf. Das geht auf dem Mac mit der Maus, weil dafür keine Zeichenfläche nötig ist.

**Suche.** Die Abschrift der Quelle macht die Textnotiz nicht auffindbar. Gefunden wird nur das Label, wie Linktext.

**Titel.** Ein Ausschnitt trägt nichts zum automatischen Titel bei (0019).

**Server.** Nichts Neues. Für ihn ist der Ausschnitt Text im Markdown; er prüft, rendert und löst nichts auf.

## Warum

Zu Text gehört oft eine Skizze, eine Formel oder eine Tabelle von Hand. Sie abzuzeichnen oder zu fotografieren erzeugt eine zweite Fassung, die veraltet. Ein Verweis hält beide Notizen bei ihrer Art (0002), gleicht pro Notiz ab wie bisher und bleibt außerhalb von inkhash als Link lesbar. Die Auswahl gibt es schon, deshalb kostet der erste Weg kaum neue Oberfläche.

## Nicht

- Keine Kopie und kein eingefrorener Stand.
- Kein Bearbeiten der Handschrift im Ausschnitt.
- Keine Ausschnitte über mehrere Seiten, keine Drehung, keine Masken.
- Keine Rückverweise („Wo wird diese Seite gezeigt?“), wie 0027.
- Keine Textabschnitte auf der Handschriftseite. Falls das später kommt, dann ebenfalls als Verweis, und zwar auf einen Abschnitt ab einer Überschrift bis zur nächsten gleicher Ebene. Keine versteckten Block-IDs im Markdown. Das braucht eine eigene ADR, weil es 0028 („kein Textelement“) ändert.
- Ältere Versionen zeigen den Ausschnitt als `!` und einen Link, der nirgends hinführt. Sie schreiben ihn beim Speichern unverändert zurück (`ExcerptTests`).

## Umsetzung

`Excerpt` (Kern) liest und schreibt das Ziel. `MarkdownCodec` kennt den Absatztyp `excerpt`. Im Editor ist ein Ausschnitt ein einzelnes `ExcerptAttachment`, das `ExcerptRenderer` beim Öffnen der Notiz zeichnet; Getipptes neben ihm landet in einem eigenen Absatz. `AppModel.openLink` öffnet bei einem Ausschnitt die Quellnotiz. Offen: Kopieren eines Ausschnitts aus dem Text heraus.
