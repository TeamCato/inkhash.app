# 0084 Suchen in der offenen Notiz

Status: angenommen. Dominik am 2026-10-25 (Suche im Text der gerade offenen Notiz, Cmd+F, mit Hervorhebung der
Treffer, Weiter und Zurück, auf Mac und iPad mit Hardware-Tastatur).

## Kontext

Cmd+F setzte bisher immer den Cursor in die Suche der Bibliothek. In einer langen Textnotiz fand man ein Wort nur mit
den Augen. Das `NSTextView` des Mac hatte die Suchleiste des Systems eingeschaltet, sie erschien aber nie: Die Notiz
liegt in einem `ScrollView` von SwiftUI, nicht in einer `NSScrollView`. Auf dem iPad gab es nichts.

## Entscheidung

1. **Cmd+F sucht dort, wo man ist.** Ist eine Textnotiz offen, öffnet Cmd+F über ihr eine eigene Suchleiste aus Papier
   (wie die Suche der Bibliothek): Feld, „2 von 5“ oder „Keine Treffer“, Pfeile zurück und weiter, Schließen.
   Ohne offene Textnotiz bleibt Cmd+F die Suche der Bibliothek. Shift+Cmd+F geht immer in die Bibliothek.
2. **Tasten.** Return und Cmd+G springen zum nächsten Treffer, Shift+Return und Shift+Cmd+G zum vorigen, nach dem
   letzten kommt wieder der erste. Escape schließt. Die Befehle stehen im Menü „Schreiben“, auf dem iPad in der
   Übersicht der Tastenkürzel. Auf dem Mac landen auch die Suchbefehle des Systems in dieser Leiste.
3. **Was trifft.** Der Wortlaut im Text, Groß- und Kleinschreibung und Akzente egal (`apfel` trifft `Äpfel`). Keine
   Unschärfe wie in der Bibliothek (ADR 0010): Hier sucht man eine Stelle, keine Notiz.
4. **Hervorhebung.** Jeder Treffer bekommt eine leise Marke in Schieferblau, der aktuelle eine kräftige in Bernstein.
   Gezeichnet wird im Layout-Manager, nicht als Attribut; der Text und der Textmarker (gelb) bleiben unberührt.
   Der aktuelle Treffer wird ins Bild gerollt, der Cursor bleibt, wo er war.
5. **Schließen wählt aus.** Escape oder Schließen nimmt die Marken weg und wählt den aktuellen Treffer aus; man kann
   gleich darüber schreiben. Ist beim Öffnen ein Stück einer Zeile ausgewählt, wird es der Suchbegriff, sonst der
   letzte.
6. **Schreiben bei offener Leiste.** Die Treffer folgen dem Text, die Ansicht springt dabei nicht.

## Folgen

- `NoteFind` im Kern (Treffer, aktueller Treffer, Weiter, Zurück), `NoteFinder` je offener Notiz, `NoteFindBar`.
- Stiftnotizen haben keine Suchleiste; dort bleibt Cmd+F die Suche der Bibliothek.
- Wache: `NoteFindTests`, `MacEditorTests.testFindMarksMatchesAndSelectsCurrentOnClose`.
