# 0035 Ausschnitte in beide Richtungen, auch mit neuer Notiz

Status: angenommen. Ziel, Auswahl, Ablage und Titel neuer Notizen geändert durch 0037: Das Element trägt kein `section` mehr, sondern das Ausschnitt-Ziel in `link`; neue Notizen haben keinen vorgegebenen Titel und liegen unter der Ausgangsnotiz.

Ergänzt 0032 (Ausschnitte aus Handschrift im Text). Ändert 0028 („kein Textelement“): Ein Text-Ausschnitt ist kein Textfeld, sondern ein Fenster auf eine Textnotiz.

## Entscheidung

**`/Ausschnitt` im Text.** Das `/`-Menü hat „Ausschnitt“. Es öffnet einen Dialog mit den Handschriftnotizen des Workspace. Wählt man eine, erscheint ihre Seite; man zieht ein Rechteck auf oder nimmt die ganze Seite. Mehrere Seiten blättert man im Dialog.

**Neue Handschrift aus dem Text.** Auf iPad und iPhone bietet der Dialog oben „Neue Handschrift“: ein Blatt zum Schreiben mit Stift oder Finger. „Anlegen und einfügen“ legt eine Handschriftnotiz im Pfad der Textnotiz an, mit dem Titel „Titel der Textnotiz – letzte Überschrift über dem Cursor“, und fügt alles Gezeichnete als Ausschnitt ein. Die neue Notiz öffnet sich nicht. Auf dem Mac gibt es diesen Weg nicht, weil dort nicht gezeichnet wird.

**Text-Ausschnitt auf der Seite.** Ein neues Element `excerpt` zeigt eine Textnotiz oder einen Abschnitt davon. Es trägt `link` (Pflicht, `inkhash://note/<id>`) und optional `section`, die Überschrift des Abschnitts. Ein Abschnitt reicht von dieser Überschrift bis zur nächsten gleicher oder höherer Ebene. Fehlt `section`, ist es die ganze Notiz. Der Text wird beim Anzeigen aus der Textnotiz gesetzt, ohne Rahmen, mit derselben Akzentlinie und Herkunftszeile wie der Handschrift-Ausschnitt im Text. Passt er nicht in die Fläche, blendet er unten aus. Wie jedes Element liegt er unter der Tinte; ein Tipp auf das Link-Zeichen öffnet die Textnotiz.

**Entstehen.** Im Bild-Menü der Werkzeugleiste steht „Text-Ausschnitt“. Der Dialog listet die Textnotizen, danach „Ganze Notiz“ und ihre Überschriften. „Neue Textnotiz“ nimmt Text direkt im Dialog auf, legt die Notiz im Pfad der Handschrift an (Titel automatisch, 0019) und setzt sie ganz ein.

**Platzhalter.** Fehlt die Notiz oder der Abschnitt, steht dort die Herkunftszeile mit dem Grund.

**Suche.** Wie 0032: Die Textnotiz wird über sich selbst gefunden, nicht über die Handschrift, auf der sie gezeigt wird.

## Warum

Zu Handschrift gehört oft Getipptes, etwa eine Liste oder ein Protokollabschnitt, und umgekehrt. Mit einem Verweis bleiben beide Notizen bei ihrer Art (0002). Eine neue Notiz direkt aus dem Dialog spart den Umweg über die Bibliothek; sie landet dort, wo die Notiz liegt, aus der sie kommt.

## Nicht

- Kein Bearbeiten des Textes auf der Seite und keiner Handschrift im Text.
- Kein Text-Ausschnitt ab einer Stelle ohne Überschrift; keine versteckten Block-IDs.
- Eine ältere App kennt `excerpt` nicht und kann eine Seite mit einem solchen Element nicht lesen. Alle Geräte müssen aktualisiert werden, wie bei 0028.
