# Architektur

## Besitz

| Ort | Darf | Darf nicht |
| --- | --- | --- |
| `Packages/InkhashCore` | Modell, Markdown, Tags, Suche, Sync-Entscheidung, lokaler Speicher, Bibliothek und ihre Bindung, HTTP-Client, PDF-Pfade lesen (`PDFInk`, nur CoreGraphics), GoodNotes-Dateien lesen (`GoodNotes`, `ZipArchive`, CoreGraphics und Compression) | SwiftUI, PencilKit, Vision |
| `App/` | Oberfläche, Zeichenfläche, Texterkennung, Keychain | Eine zweite Sync-Wahrheit |
| `Server/` | Dateien, Revisionen, Auth | Markdown verstehen, Striche lesen, Tags berechnen, suchen |

Das Modell der App ist nach Aufgaben geteilt (`App/Shared/Model`). `WorkspaceRegistry` hält Workspaces und Server des Geräts (`setup.json`), ihre Bibliotheken und Bilder, ohne Netz. `ServerSessions` meldet an und ab, hält die Tokens und prüft Adressen. `NoteLibrary` hält und bearbeitet die Notizen des aktuellen Workspace und sagt nach jeder Änderung Bescheid. `SyncCoordinator` entscheidet, wann abgeglichen wird, und gleicht ab. `AppModel` hält nur, wo man gerade ist (Bereich, Suche, Auswahl), und die Abläufe, die mehrere Teile brauchen, etwa Workspace wechseln oder Anmelden und danach abgleichen. Fehler und Hinweise gehen an eine gemeinsame `StatusLine`. Was ohne Oberfläche gilt, steht im Kern und ist dort getestet: Listen, Baum und Schlagwörter in `NoteListing`, Adressen in `ServerAddress`.

Suche ist eine reine Funktion in `NoteSearch`. Die Bibliothek ruft sie über den Cache auf. Es gibt keinen Such-Endpunkt.

Import sitzt in zwei Hälften. Im Kern liest `PDFInk` die Vektorpfade eines PDFs seitenweise als Polylinien, `GoodNotes` liest eine `.goodnotes`-Datei (ZIP über `ZipArchive`, Protobuf, LZ4 und TPL in `GoodNotesWire`) als Seiten mit Strichen, Bildern und importierten PDF-Seiten. `InkImport` in der App macht daraus `PKStroke`s, eine `PKDrawing` und `image`-Elemente als JPEG. `NoteLibrary.importFile` erkennt die Art an den ersten Bytes und legt die Notizen an. `tools/PdfInkSpike.swift` ist dasselbe als Kommandozeile für echte Dateien (`make import-spike FILE=…`, PDF oder `.goodnotes`). Siehe ADR 0024 und 0041.

Papier gehört zur Notiz (`Note.paper`, `Paper` im Kern, mit optionalem Abstand `spacing`, ADR 0047). `PaperArt` in der App zeichnet Linien, Karos und Punkte in Seitenkoordinaten mit `Paper.shownSpacing`: auf dem iPad über `PaperPatternView`, die nur den sichtbaren Ausschnitt deckt und dem Scrollen folgt, auf dem Mac über `PaperPatternCanvas`. Die Farbe ist der Hintergrund der ganzen Notiz. `PageImage` rendert einen Ausschnitt einer Seite für Ausschnitte (ohne Papier) und für die Miniaturen in `PageOverview` (mit Papier). Seiten ordnet und löscht `Note.reorderPages`, `movePage` und `removePage`; Abschrift und Schlagwörter folgen. Siehe ADR 0042.

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
deploy                   Release-Paket, systemd-Unit, install.sh und Compose. Siehe docs/DEPLOY.md
.github/workflows        Server testen, Release-Paket und Image veröffentlichen (ADR 0039)
docs                     Produkt, Vertrag, Entscheidungen, Fallen
tools                    Werkzeuge, mit swiftc gegen die Quellen gebaut: Icon, Import-Spike
```

## Sync

Zuerst holen, dann hochladen, dann noch einmal holen, damit der eigene Schreibvorgang den Cursor nachzieht. Holen läuft in Seiten, bis `hasMore` falsch ist. Blobs gehen vor der Notiz, die sie nennt. Konflikte werden nicht zusammengeführt. Auf dem Server ist die Notizdatei die Wahrheit. Das Änderungsprotokoll wird danach geschrieben und beim Start repariert, siehe ADR 0015. Auf dem Server gehört die Sitzung zu einem Account, und der Account zu einem eigenen Ablageverzeichnis, siehe ADR 0013. Auf dem Gerät gibt es pro Workspace eine Bibliothek ohne Account, Server und Workspaces stehen in `setup.json` (`Workspaces.open`). `Library.bind` hängt eine Bibliothek an Account und Server-Workspace und löst sie beim Wechsel vom alten. `SyncCoordinator.sync` gleicht jeden verbundenen Workspace ab, dessen Server eine Sitzung hat. Siehe ADR 0020. Davor gleicht `LookSyncer` pro Server Aussehen und Reihenfolge der Workspaces ab (ADR 0043). Ohne Anmeldung läuft kein Abgleich, sonst ändert sich nichts. Siehe ADR 0017.

## Handschrift auf dem Mac

`PKCanvasView` gibt es in diesem SDK nur für iPhone und iPad. Der Mac zeigt `PKDrawing` als Bild und sucht in der Abschrift. Neue Striche entstehen auf dem iPad, notfalls mit dem Finger auf dem iPhone (ADR 0026).

## Darstellung

Eine Notiz füllt die Detailfläche, das Blatt ist die Fläche (ADR 0018). Text sitzt auf diesem Blatt in einem einzigen Textfeld (`NoteTextView`, `EditorEngine`, ADR 0025), ohne feste Werkzeugleiste; markierter Text bekommt eine schwebende Leiste über dem Block (`FormatBar`, ADR 0023). Das `/`-Menü und das `[[`-Menü (`NoteLinkMenu`) liegen unter der Cursorzeile, kein Popover, damit das Textfeld den Fokus behält. Nur „Link“ aus dem `/`-Menü öffnet ein Popover am Cursor (`LinkInsertEditor`), weil es zwei Felder braucht; danach bekommt das Textfeld den Fokus zurück. Ziele aus allen Linkfeldern laufen durch `LinkTarget.normalize` im Kern (ADR 0031). Tabellenzeilen sind Absätze mit Tabulatoren; `MarkerLayoutManager` zeichnet das Gitter (ADR 0027). Ein Ausschnitt ist ein Absatz aus einem `ExcerptAttachment`; `ExcerptRenderer` zeichnet den Seitenbereich aus der Quellnotiz, die `ExcerptSource` der Sitzung liefert (ADR 0032). Ausschnitte haben ein Ziel (`ExcerptTarget` im Kern, Seite oder Text) und eine Darstellung (`ExcerptCards`: `ExcerptCard` für Seiten, `TextExcerptCard` für Text), im Text als `ExcerptAttachment`, auf der Seite als `excerpt`-Element über `ExcerptElementImages`. `ElementContent` liefert jedem Element sein Bild, `ExcerptSource.current` die Notizen des Workspace. `ExcerptPicker` wählt in beide Richtungen und öffnet für neue Notizen ihren eigenen Editor (ADR 0035, 0037). Tabellen tragen ihr `TableFormat` an der ersten Zeile, `TableRowLayout` an jeder Zeile sagt dem Layout-Manager, wo die Spalten liegen (ADR 0036). Editor-Tests laufen mit `make app-test` im iPad-Simulator gegen ein echtes `UITextView`. Handschrift ist eine eingepasste Seite, die zoomt, ohne die Strichkoordinaten zu ändern. Unter der Tinte liegen die Elemente der Seite (`ElementView`, gezeichnet von `ElementRenderer`), darüber Auswahl und Vorschau; beides in Seitenkoordinaten im `PKCanvasView` (`InkPageCanvas.Coordinator`). Die Werkzeugleiste (`InkToolRail`) steht immer offen am linken Rand, bei schmaler Breite unten. `InkEditorState` verbindet Seite und SwiftUI: Auswahl, Scrollstand für die Link-Zeichen, Befehle der Auswahlleiste (ADR 0028). Links folgen über `AppModel.openLink`; `inkhash://note/<id>` öffnet die Notiz. Flächen über dem Blatt sind Papier, nicht Glas (`inkSurface`, ADR 0029). Das Fenster bleibt hell. Siehe ADR 0011, 0012 und 0018.

## Navigation

Zwei Spalten: Seitenleiste und Notiz. Die Seitenleiste ist Logo, Workspace-Umschalter, Suche, dann der Baum: Ordner aufklappbar, Notizen als Blätter (`NoteTree`, ADR 0022). `#tag` im Suchfeld filtert den Baum nach Schlagwort; passende Schlagwörter erscheinen als Kapseln unter dem Feld. Textsuche, Favoriten und Papierkorb sind flache Listen an derselben Stelle; Favoriten und Papierkorb liegen als Knöpfe unten neben Status und Zahnrad. Alles unter dem Umschalter gehört zum aktuellen Workspace. Titel und Pfad einer Notiz stehen oben links auf dem Blatt (`NoteHeader`) und werden dort per Klick geändert; der Pfad ist das `folder` der Notiz. Workspaces und Server richtet man hinter dem Zahnrad ein. Auf dem iPad klappt die Seitenleiste beim Öffnen einer Notiz weg und schwebt danach über dem Blatt; auf dem Mac bleibt sie offen, außer im schmalen Fenster (`RootView.placeSidebar`, ADR 0030).
