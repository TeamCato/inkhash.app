# Architektur

## Besitz

| Ort | Darf | Darf nicht |
| --- | --- | --- |
| `Packages/InkhashCore` | Modell, Markdown, Tags, Suche, Sync-Entscheidung, lokaler Speicher, Bibliothek und ihre Bindung, HTTP-Client, PDF-Pfade lesen (`PDFInk`, nur CoreGraphics) | SwiftUI, PencilKit, Vision |
| `App/` | Oberfläche, Zeichenfläche, Texterkennung, Keychain | Eine zweite Sync-Wahrheit |
| `Server/` | Dateien, Revisionen, Auth | Markdown verstehen, Striche lesen, Tags berechnen, suchen |

Suche ist eine reine Funktion in `NoteSearch`. Die Bibliothek ruft sie über den Cache auf. Es gibt keinen Such-Endpunkt.

Import sitzt in zwei Hälften: `PDFInk` im Kern liest die Vektorpfade eines PDFs seitenweise als Polylinien, `InkImport` in der App macht daraus `PKStroke`s und eine `PKDrawing`. `AppModel.importPDF` legt die Notiz an. `tools/PdfInkSpike.swift` ist dasselbe als Kommandozeile für echte Exporte (`make import-spike`). Siehe ADR 0024.

Texterkennung sitzt in `HandwritingRecognizer`. Sie rendert die Zeichnung, liest sie mit Vision und gibt Wörter an `Hashtags` weiter. Das Ergebnis schreibt der Client auf die Seite, dann synchronisiert er es wie jeden anderen Feldwert.

## Verzeichnisse

```
AGENTS.md
project.yml              XcodeGen. Nicht die xcodeproj von Hand ändern.
Packages/InkhashCore     gemeinsamer Kern, ohne UI
App/Shared               SwiftUI für iPad, iPhone und Mac
App/iOS                  Einstieg iPad und iPhone
App/macOS                Einstieg Mac
Server                   TypeScript auf Node, ohne Framework
deploy                   Release-Paket, systemd-Unit, install.sh, Compose und Caddy. Siehe docs/DEPLOY.md
.github/workflows        Server testen, Release-Paket und Image veröffentlichen (ADR 0039)
docs                     Produkt, Vertrag, Entscheidungen, Fallen
tools                    Werkzeuge, mit swiftc gegen die Quellen gebaut: Icon, Import-Spike
```

## Sync

Zuerst holen, dann hochladen, dann noch einmal holen, damit der eigene Schreibvorgang den Cursor nachzieht. Holen läuft in Seiten, bis `hasMore` falsch ist. Blobs gehen vor der Notiz, die sie nennt. Konflikte werden nicht zusammengeführt. Auf dem Server ist die Notizdatei die Wahrheit. Das Änderungsprotokoll wird danach geschrieben und beim Start repariert, siehe ADR 0015. Auf dem Server gehört die Sitzung zu einem Account, und der Account zu einem eigenen Ablageverzeichnis, siehe ADR 0013. Auf dem Gerät gibt es pro Workspace eine Bibliothek ohne Account, Server und Workspaces stehen in `setup.json` (`Workspaces.open`). `Library.bind` hängt eine Bibliothek an Account und Server-Workspace und löst sie beim Wechsel vom alten. `AppModel.sync` gleicht jeden verbundenen Workspace ab, dessen Server eine Sitzung hat. Siehe ADR 0020. Ohne Anmeldung läuft kein Abgleich, sonst ändert sich nichts. Siehe ADR 0017.

## Handschrift auf dem Mac

`PKCanvasView` gibt es in diesem SDK nur für iPhone und iPad. Der Mac zeigt `PKDrawing` als Bild und sucht in der Abschrift. Neue Striche entstehen auf dem iPad, notfalls mit dem Finger auf dem iPhone (ADR 0026).

## Darstellung

Eine Notiz füllt die Detailfläche, das Blatt ist die Fläche (ADR 0018). Text sitzt auf diesem Blatt in einem einzigen Textfeld (`NoteTextView`, `EditorEngine`, ADR 0025), ohne feste Werkzeugleiste; markierter Text bekommt eine schwebende Leiste über dem Block (`FormatBar`, ADR 0023). Das `/`-Menü und das `[[`-Menü (`NoteLinkMenu`) liegen unter der Cursorzeile, kein Popover, damit das Textfeld den Fokus behält. Nur „Link“ aus dem `/`-Menü öffnet ein Popover am Cursor (`LinkInsertEditor`), weil es zwei Felder braucht; danach bekommt das Textfeld den Fokus zurück. Ziele aus allen Linkfeldern laufen durch `LinkTarget.normalize` im Kern (ADR 0031). Tabellenzeilen sind Absätze mit Tabulatoren; `MarkerLayoutManager` zeichnet das Gitter (ADR 0027). Ein Ausschnitt ist ein Absatz aus einem `ExcerptAttachment`; `ExcerptRenderer` zeichnet den Seitenbereich aus der Quellnotiz, die `ExcerptSource` der Sitzung liefert (ADR 0032). Ausschnitte haben ein Ziel (`ExcerptTarget` im Kern, Seite oder Text) und eine Darstellung (`ExcerptCards`: `ExcerptCard` für Seiten, `TextExcerptCard` für Text), im Text als `ExcerptAttachment`, auf der Seite als `excerpt`-Element über `ExcerptElementImages`. `ElementContent` liefert jedem Element sein Bild, `ExcerptSource.current` die Notizen des Workspace. `ExcerptPicker` wählt in beide Richtungen und öffnet für neue Notizen ihren eigenen Editor (ADR 0035, 0037). Tabellen tragen ihr `TableFormat` an der ersten Zeile, `TableRowLayout` an jeder Zeile sagt dem Layout-Manager, wo die Spalten liegen (ADR 0036). Editor-Tests laufen mit `make app-test` im iPad-Simulator gegen ein echtes `UITextView`. Handschrift ist eine eingepasste Seite, die zoomt, ohne die Strichkoordinaten zu ändern. Unter der Tinte liegen die Elemente der Seite (`ElementView`, gezeichnet von `ElementRenderer`), darüber Auswahl und Vorschau; beides in Seitenkoordinaten im `PKCanvasView` (`InkPageCanvas.Coordinator`). Die Werkzeugleiste (`InkToolRail`) steht immer offen am linken Rand, bei schmaler Breite unten. `InkEditorState` verbindet Seite und SwiftUI: Auswahl, Scrollstand für die Link-Zeichen, Befehle der Auswahlleiste (ADR 0028). Links folgen über `AppModel.openLink`; `inkhash://note/<id>` öffnet die Notiz. Flächen über dem Blatt sind Papier, nicht Glas (`inkSurface`, ADR 0029). Das Fenster bleibt hell. Siehe ADR 0011, 0012 und 0018.

## Navigation

Zwei Spalten: Seitenleiste und Notiz. Die Seitenleiste ist Logo, Workspace-Umschalter, Suche, dann der Baum: Ordner aufklappbar, Notizen als Blätter (`NoteTree`, ADR 0022). `#tag` im Suchfeld filtert den Baum nach Schlagwort; passende Schlagwörter erscheinen als Kapseln unter dem Feld. Textsuche, Favoriten und Papierkorb sind flache Listen an derselben Stelle; Favoriten und Papierkorb liegen als Knöpfe unten neben Status und Zahnrad. Alles unter dem Umschalter gehört zum aktuellen Workspace. Titel und Pfad einer Notiz stehen oben links auf dem Blatt (`NoteHeader`) und werden dort per Klick geändert; der Pfad ist das `folder` der Notiz. Workspaces und Server richtet man hinter dem Zahnrad ein. Auf dem iPad klappt die Seitenleiste beim Öffnen einer Notiz weg und schwebt danach über dem Blatt; auf dem Mac bleibt sie offen, außer im schmalen Fenster (`RootView.placeSidebar`, ADR 0030).
