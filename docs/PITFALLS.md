# Fallen

Anhängen, nicht umschreiben. Die Wache ist der Teil, der schützt.

## P-001 · PKDrawing ist Bytes

**Symptom.** Handschrift kommt leer oder kaputt auf dem anderen Gerät an.
**Ursache.** Die Zeichnung wurde als Text oder als falsch kodierter String gespeichert.
**Wache.** Blobs sind Rohbytes. Der Hash ist SHA-256 dieser Bytes. `LocalStore.putBlob` und der Server prüfen das.

## P-002 · Markdown-Runde ist kanonisch

**Symptom.** Eine Notiz verändert sich beim Öffnen, ohne dass jemand tippt.
**Ursache.** Der Parser wirft Syntax weg, die er nicht kennt, oder serialisiert anders, als er liest.
**Wache.** `MarkdownTests.testRoundtripDocument`. Öffnen markiert die Notiz nicht als dirty. `applyMarkdown` gibt false zurück, wenn sich nichts geändert hat.

## P-003 · Schreiben ohne baseRevision überschreibt

**Symptom.** Die Fassung des anderen Geräts ist weg.
**Ursache.** Ein PUT legt neu an oder setzt die Revision nicht voraus.
**Wache.** Server-Test „create, update, conflict, and tombstone“ in `Server/test/store.test.ts`. `decide` in `SyncTests`.

## P-004 · Pfade aus IDs bauen

**Symptom.** Eine Anfrage liest außerhalb des Datenverzeichnisses.
**Ursache.** Die ID landet ungeprüft in einem Pfad.
**Wache.** Server-Test „rejects path escape and bad tags“ in `Server/test/store.test.ts`. Nur kleingeschriebene UUIDs und 64 Hex-Zeichen.

## P-005 · UUID-Großschreibung

**Symptom.** Dieselbe Notiz existiert zweimal, oder der Server lehnt sie ab.
**Ursache.** `UUID.uuidString` ist großgeschrieben. Der Server speichert klein.
**Wache.** `FixtureTests.testFixturesDecodeAndIdsStayLowercase`. Encoder schreibt `lowercased()`.

## P-006 · Datum nicht über DateFormatter

**Symptom.** `updatedAt` hängt von der Region des Geräts ab und lässt sich nicht vergleichen.
**Ursache.** `DateFormatter` mit der Nutzer-Locale.
**Wache.** `InkhashTime` benutzt `ISO8601DateFormatter`. Der Server schreibt `YYYY-MM-DDTHH:MM:SSZ`.

## P-007 · Grabstein statt Löschen der Datei

**Symptom.** Das andere Gerät holt die Notiz wieder, oder behält sie für immer.
**Ursache.** Die Datei wurde entfernt, statt `deletedAt` zu setzen. Das andere Gerät sieht keine Änderung.
**Wache.** `Store.deleteNote` (`Server/store.ts`) behält den Körper und erhöht die Revision. Der Client blendet `deletedAt` aus.

## P-008 · Blobs vor der Notiz

**Symptom.** Die Seite ist da, die Zeichnung 404.
**Ursache.** Die Notiz wurde vor ihrem Blob hochgeladen.
**Wache.** `SyncTests.testInkUploadsBlobBeforeNote` erwartet die Reihenfolge `blob`, dann `put`.

## P-009 · Cursor nach dem eigenen Push

**Symptom.** Der nächste Abgleich lädt die eigene Änderung noch einmal, oder der Cursor bleibt auf 0.
**Ursache.** Der Cursor wurde vor dem Hochladen gesetzt und danach nicht nachgezogen.
**Wache.** `Syncer` holt nach dem Push ein zweites Mal. `testPushCreateAndPull` erwartet Cursor 1.

## P-010 · Textfeld nicht bei jedem SwiftUI-Update überschreiben

**Symptom.** Der Cursor springt, oder gerade getippte Zeichen verschwinden.
**Ursache.** `updateUIView` setzt den Text, obwohl die Änderung aus dem Feld selbst kam.
**Wache.** `NoteTextView` setzt den Text nur einmal beim Anlegen; danach gehört er dem Textfeld, und `updateUIView`/`updateNSView` schreiben nichts zurück. Eigene Änderungen der `EditorEngine` laufen mit einem `programmatic`-Flag. Nicht durch ein Popover für `/` den Fokus stehlen. Das Menü liegt unter der Cursorzeile.

## P-011 · Smarte Anführungszeichen

**Symptom.** `**` oder `"` kommt als typografisches Zeichen an, die Erkennung der Marker scheitert.
**Ursache.** Das System ersetzt Zeichen, während Markdown erwartet wird.
**Wache.** Quote-, Dash- und Text-Ersetzung sind am Textfeld aus.

## P-012 · Zeichnung nicht bei jedem Punkt zurückladen

**Symptom.** Der Strich flackert oder die Undo-Liste ist leer.
**Ursache.** `canvas.drawing` wird gesetzt, während der Stift noch liegt, oder bei jedem SwiftUI-Durchlauf.
**Wache.** `InkPageCanvas` lädt nur, wenn der Hash abweicht und der Stift nicht aktiv ist. Speichern ist entprellt, plus einmal am Ende des Strichs.

## P-013 · Werkzeugleiste des Stifts

**Symptom.** Der System-Stiftwähler liegt über dem Blatt, oder jede Seite reißt sich den Fokus.
**Ursache.** `PKToolPicker` und `becomeFirstResponder` in `didMoveToWindow`.
**Wache.** Die iPad-Seite setzt `canvas.tool` aus `InkToolState`. Es gibt keinen System-Picker. Der Fokus kommt vom Stift, nicht vom Erscheinen der Seite. Siehe ADR 0012.

## P-014 · Überschrift und Schlagwort

**Symptom.** `# Plan` wird zum Tag, oder `#launch` wird zur Überschrift.
**Ursache.** Jedes `#` wird gleich behandelt.
**Wache.** `HashtagTests` und `MarkdownTests.testHashTagIsNotAHeading`. Im Markdown ist `# ` mit Leerzeichen eine Überschrift, `#wort` ein Tag. In der Handschrift darf zwischen `#` und Wort ein Leerzeichen stehen.

## P-015 · Erkennung nicht auf dem Server, und nicht mit Sprachkorrektur

**Symptom.** Tags werden zu Wörterbuchwörtern, oder der Server bekommt Bilder.
**Ursache.** Vision mit `usesLanguageCorrection`, oder OCR auf dem Server.
**Wache.** `HandwritingRecognizer` setzt `usesLanguageCorrection = false` und läuft auf dem Gerät. Der Server speichert `transcript` und `tags` als opaque Felder. Eine leere Erkennung auf einer nicht leeren Seite löscht eine vorhandene Abschrift nicht: `Note.applyInkReading(…, pageHasInk:)`, Test `NoteReadingTests`.

## P-016 · Suche ist keine Synonym-Suche

**Symptom.** Jemand erwartet, dass „Besprechung“ auch „Meeting“ findet, und baut dafür ein Modell ein.
**Ursache.** „Nicht der exakte Wortlaut“ wird als semantische Suche gelesen.
**Wache.** `SearchTests`. Getroffen wird über Normalisierung, Präfix ab drei Zeichen, kleine Edit-Distanz und Tags. Synonyme sind ausgeschlossen, siehe ADR 0010.

## P-017 · Token nicht loggen

**Symptom.** Der Bearer-Token oder eine Zeichnung steht in den Server-Logs.
**Ursache.** Der Request wird samt Headern geloggt.
**Wache.** `route` in `Server/inkhashd.ts` schreibt nur Methode und Pfad. Einzige Ausnahme ist der Setup-Token beim Start eines Servers ohne Accounts: Er legt nur den Admin an und gilt danach nicht mehr (ADR 0021).

## P-018 · Setup-Token nicht ausdenken

**Symptom.** Ein frisch gestarteter Server im LAN lässt sich mit einem erratbaren Token wie `dev` einrichten.
**Ursache.** Der Setup-Token kam aus der Umgebung und durfte kurz sein.
**Wache.** ADR 0021. Der Server erzeugt den Token selbst, 24 Zufallsbytes, nur im Speicher, und nur solange es keinen Account gibt. `INKHASH_TOKEN` wird ignoriert. `make server` bindet trotzdem `127.0.0.1`. Test „setup token is random per start and gone once an account exists“.

## P-020 · Registrierung ist nicht offen

**Symptom.** Jeder im Netz kann sich einen Account anlegen, oder der Setup-Token gilt als Dauer-Login.
**Ursache.** `POST /v1/accounts` ohne Schranke, oder der Setup-Token als Bearer für Notizen.
**Wache.** `Server/test/http.test.ts`, „setup creates the admin once …“ und „only the admin creates accounts …“. Der erste Account braucht den Setup-Token, danach legt nur der Admin an. Der Setup-Token öffnet keine Notizen. Acht Fehlversuche sperren den Namen, 30 Fehlversuche die Adresse. ADR 0013, ADR 0016, ADR 0021.

## P-019 · Glas nicht auf die Seite

**Symptom.** Die Tinte wirkt milchig, oder die Leiste ist eine deckende Fläche und das Glas verschwindet.
**Ursache.** `glassEffect` liegt auf dem Blatt, oder das Fenster ist mit `Ink.paper` vollflächig übermalt.
**Wache.** ADR 0011. Das Blatt ist deckendes Papier. Glas liegt auf Suche, Tags, Menü und Banner. Der Schreibtisch ist der Verlauf dahinter.
**Nachtrag.** Überholt durch ADR 0029: über dem Blatt liegt Papier statt Glas, `inkSurface` in `Theme.swift`. Das Blatt bleibt deckend.

## P-021 · Absturz zwischen Notiz und Protokoll

**Symptom.** Eine Änderung kommt auf dem anderen Gerät nie an. Das schreibende Gerät meldet beim nächsten Versuch einen Konflikt mit seinem eigenen Text.
**Ursache.** Die Notizdatei war geschrieben, die Zeile im Änderungsprotokoll nicht. Oder der Zähler lag in einer eigenen Datei und lief dem Protokoll davon.
**Wache.** ADR 0015. Die Notizdatei ist die Wahrheit. `Store.load` vergleicht beim Start jede Notiz mit dem Protokoll und trägt Fehlendes nach. Ein wiederholter Schreibvorgang mit gleichem Inhalt bekommt 200 statt 409. Tests „note written without its log entry is announced after restart“, „retry of a stored write answers with the stored note“, „torn last log line is cut off, a broken middle line is fatal“.

## P-022 · Synchrones Hashing blockiert den Server

**Symptom.** Während jemand Anmeldungen durchprobiert, antwortet der Server niemandem.
**Ursache.** `pbkdf2Sync` mit vielen Runden läuft auf dem Event-Loop. Die Sperre pro Name hilft nicht gegen wechselnde Namen.
**Wache.** ADR 0016. `Accounts` hasht mit `pbkdf2` asynchron und zählt Fehlversuche zusätzlich pro Adresse. Tests „wrong passwords lock the name“, „guessing the setup token is slowed down“.

## P-023 · Docker-Volume gehört root

**Symptom.** Der Container startet nach dem Update, aber jedes Schreiben endet mit 500 und `EACCES`.
**Ursache.** Das Image läuft als `node`. Ein Volume aus der Zeit, als der Container root war, gehört noch root.
**Wache.** Einmalig: `docker compose run --rm -u root inkhash chown -R node:node /data`, bei einem Bind-Mount `sudo chown -R 1000:1000 data`. Siehe `docs/RELEASE.md`. Ist das Datenverzeichnis beim Start nicht schreibbar, beendet sich der Server mit `cannot write <pfad> as uid <n>` statt mit einem Stacktrace (`openAccounts` in `Server/inkhashd.ts`).

## P-024 · Seiten im Änderungsprotokoll

**Symptom.** Ein neues Gerät hat nach dem ersten Abgleich nur einen Teil der Notizen.
**Ursache.** `/v1/changes` liefert höchstens `limit` Einträge. Der Client hat `hasMore` nicht beachtet.
**Wache.** `Syncer.pull` holt, solange `hasMore` gilt, und bricht ab, wenn der Cursor nicht weiterläuft. `SyncTests.testPullFollowsPages`.

## P-025 · Accountwechsel mit alten Revisionen

**Symptom.** Nach dem Anmelden an einem anderen Account kommen lokale Notizen nie an, oder jede Notiz meldet einen Konflikt.
**Ursache.** Die Notizen tragen Revisionen und `dirty: false` aus dem alten Account. Der Abgleich lädt nur geänderte Notizen hoch, und eine fremde Revision passt auf keinem anderen Server.
**Wache.** ADR 0017. `Library.bind` setzt beim Wechsel alles auf Revision 0 und `dirty`, entfernt Grabsteine und macht eine liegengebliebene Server-Fassung zu einer eigenen Notiz. Gleicher Inhalt auf beiden Seiten ist kein Konflikt (`decide`). Ein 409 beim Hochladen wird ein Konflikt mit beiden Fassungen, statt den Abgleich abzubrechen. `LibraryTests`, `SyncTests.testSameContentOnBothSidesIsNoConflict`, `SyncTests.testConflictOnPushKeepsBothAndContinues`.

## P-026 · Ohne Server muss alles gehen

**Symptom.** Ohne Anmeldung zeigt die App einen Fehler als Status, oder eine Funktion wartet auf den Server.
**Ursache.** Code, der einen Server voraussetzt, etwa einen Abgleich nach jeder Änderung anstößt und dessen Fehlschlag meldet.
**Wache.** `SyncCoordinator.isEnabled`. Ohne Sitzung startet `SyncCoordinator.schedule` nichts, und der Status sagt „Nur auf diesem Gerät.“ `LibraryTests.testFreshLibraryWorksWithoutAccount`.

## P-027 · Abgelaufene Sitzung sieht aus wie angemeldet

**Symptom.** Nach 90 Tagen ohne Benutzung steht nur „Anmeldung abgelehnt.“ im Status. Die Einstellungen zeigen weiter „Angemeldet als …“, und jeder Abgleich scheitert still.
**Ursache.** Ein 401 auf eine Anfrage mit Sitzung wurde wie jeder andere Fehler als Status gemeldet. Ein 401 beim Anmelden selbst heißt dagegen nur: falsches Passwort.
**Wache.** `ServerSessions.expire(_:ifStill:)` läuft nur bei `sync` und `remoteWorkspaces`, nicht beim Anmelden. Die Sitzung gilt pro Server. Es vergleicht den Token vom Start der Anfrage mit dem aktuellen. Die Bibliothek bleibt gebunden, `ExpiredSessionBanner` bietet das Anmelden an. Tests `SessionTests.testAnOldRequestDoesNotEndANewSession`, `testAnExpiredSessionEndsAndSaysSo`.

## P-028 · Block-Kürzel lassen das Zeichen stehen

**Symptom.** `# hallo` wird zur Überschrift `#hallo`, gespeichert als `# #hallo`.
**Ursache.** Nach dem Leerzeichen wechselte nur der Blocktyp im Modell. Das Textfeld behielt das `#`, bis SwiftUI den leeren Block zurückschob, und schnelles Tippen landete dahinter.
**Wache.** `EditorEngine.applyShortcut` löscht das Kürzel im selben Aufruf, in dem es erkannt wird, und setzt den Stil des Absatzes. Nach einem geschlossenen Inline-Marker (`*x*`, `**x**`, `` `x` ``) gehen die Tippattribute auf normal zurück. Tests `BlockEditingTests.testShortcutsTurnTheLineAndLeaveNoMarker`, `testTypingAfterBoldIsPlain`.

## P-029 · Return öffnet auf dem iPad das Neu-Menü

**Symptom.** Mit Hardware-Tastatur macht Return keine neue Zeile, sondern öffnet das Menü für neue Notizen.
**Ursache.** iPadOS gibt Return an die Primäraktion der Toolbar, bevor das Textfeld es sieht.
**Wache.** `InkNoteTextView.keyCommands` registriert Return mit `wantsPriorityOverSystemBehavior` und ruft `returnPressed`, das an `EditorEngine.returnKey` geht (P-041).

## P-030 · Fette Überschrift wird zu `**`

**Symptom.** Eine Überschrift speichert sich als `# **Titel**`, oder jeder Tastendruck in ihr erzeugt Sterne.
**Ursache.** Überschriften sind fett gesetzt, und die Rückübersetzung aus dem Textfeld liest jede fette Schrift als `**`.
**Wache.** `RichText.spans(from:type:)` und `RichText.reconcile(_:cursor:type:)` kennen den Blocktyp und ignorieren Fett in Überschriften. Folge: `**x**` innerhalb einer Überschrift hat keine eigene Wirkung.

## P-031 · Ältere App leert Ordner und Favorit

**Symptom.** Nach einer Änderung auf einem Gerät mit älterer App ist eine Notiz wieder ohne Ordner und kein Favorit mehr.
**Ursache.** Apps von vor ADR 0020 kennen `folder` und `favorite` nicht und schicken sie nicht mit. Der Server liest Fehlendes als `""` und `false`.
**Wache.** Keine im Code. Alle Geräte auf denselben Stand bringen. Der Server muss Fehlendes so lesen, damit ältere Apps überhaupt schreiben können (`store.test.ts`, „folder and favorite are checked …“).

## P-032 · Workspace `main` bleibt ohne Präfix

**Symptom.** Nach dem Update lädt ein Gerät alle Notizen noch einmal hoch, oder ältere Apps sehen die Notizen nicht mehr.
**Ursache.** Der Bindungsschlüssel oder die Route für `main` hat sich geändert.
**Wache.** `Workspaces.bindingKey` gibt für `main` die nackte Account-ID zurück (`WorkspaceTests.testBindingKeySeparatesWorkspacesOfOneAccount`), `APIClient` nutzt für `main` die Routen ohne Präfix, und der Server-Test „workspaces keep their notes apart …“ prüft beide Wege.

## P-033 · Textblock läuft rechts aus dem Blatt

**Symptom.** Eine lange Zeile bricht nicht um, sondern läuft über den rechten Rand, vor allem in schmalen Spalten.
**Ursache.** Ein `UITextView` ohne Scrollen meldet SwiftUI seine einzeilige Breite als eigene Größe. Die Höhe wurde außerdem geschätzt statt gemessen.
**Wache.** `IOSNoteText` und `MacNoteText` implementieren `sizeThatFits`: Sie nehmen die angebotene Breite und messen die Höhe über `EditorEngine.height(for:)`, siehe P-037. Kein automatischer Test für `sizeThatFits`; das Messen selbst prüft `BlockEditingTests.testMeasuringLeavesTheContainerAlone`. Prüfen: lange Zeile im iPad-Hochformat mit offener Liste.

## P-034 · Zeichnung landet auf der falschen Seite

**Symptom.** Was man auf einer Handschriftseite schreibt, erscheint nach dem Blättern auf der falschen Seite, oder eine Seite zeigt ihre eigenen Striche nicht.
**Ursache.** Zwei Dinge. Die Zeichenfläche speichert verzögert (0,45 s), und der verzögerte Auftrag fragte beim Ausführen nach der gerade gezeigten Seite, nicht nach der, auf der gezeichnet wurde. Und `PKCanvasView` malt eine Zeichnung nicht, die es bekam, bevor Größe und Zoom feststanden.
**Wache.** `InkPageCanvas.Coordinator` merkt sich seine `pageID` und gibt sie bei jedem Speichern mit. Wechselt die Seite oder verschwindet die Fläche, wird Ausstehendes zuerst für die alte Seite gesichert (`flush`). Nach dem Anlegen und nach jeder Zoom-Änderung gibt `redrawSoon` die Zeichnung noch einmal herein. Test `InkPageCanvasTests.testAWaitingDrawingIsSavedForItsPage` für das Sichern; das Malen nach dem Layout nur von Hand: auf Seite 1 schreiben, sofort blättern, auf Seite 2 schreiben, zurück.

## P-035 · Anmelden im Simulator scheitert am Schlüsselbund

**Symptom.** Im Simulator legt der Server den Account an, die App meldet aber einen Fehler und bleibt abgemeldet.
**Ursache.** Ohne Signatur verweigert der Schlüsselbund das Speichern der Sitzung.
**Wache.** `make ipad` signiert ad hoc (`CODE_SIGN_IDENTITY=-`). Die App meldet den Fall als Schlüsselbund-Fehler mit Status, nicht als „Abgleich fehlgeschlagen“.

## P-036 · PDF-Pfade: Callbacks ohne Kontext, Farben über Farbräume, y nach oben

**Symptom.** Der Import kompiliert nicht („C function pointer cannot be formed from a closure that captures context“), oder alle Striche sind schwarz, oder die Seite steht auf dem Kopf.
**Ursache.** Drei Dinge an `CGPDFScanner`. Die Operator-Callbacks sind C-Funktionszeiger; auch der Aufruf einer statischen Methode der eigenen Klasse zählt als Einfangen. Farben kommen in PDFs aus CoreGraphics und GoodNotes nicht nur als `RG`/`rg`, sondern über benannte Farbräume mit `sc`/`scn`. Und der PDF-Ursprung liegt unten links.
**Wache.** `PDFInk.swift`: Helfer für die Callbacks sind freie Funktionen auf Dateiebene. `popColor` liest `sc`/`scn` nach Operandenzahl. `PDFInkTests.testReadsPathsScaledAndFlipped` prüft Farbe, Skalierung und die Spiegelung der y-Achse.

## P-037 · Messen darf den Textcontainer nicht anfassen

**Symptom.** Auf dem Mac bricht ein Block plötzlich auf 40 Punkt Breite um, Zeile für Zeile, und die Zeilen darunter liegen über ihm. Oft nach dem Markieren, wenn die Formatleiste erscheint.
**Ursache.** `sizeThatFits` setzte die `containerSize` des echten `NSTextView`. SwiftUI misst in einem `HStack` auch mit Breite 0; der Container wurde dabei schmal. Blieb die Endgröße gleich, setzte SwiftUI den Rahmen nicht neu, und der Container blieb schmal.
**Wache.** `EditorEngine.height(for:)` misst nur dann am echten Layout, wenn dessen Container genau so breit ist wie gefragt und nicht in der Höhe begrenzt; sonst auf einem eigenen `NSLayoutManager`. UIKit setzt den Container eines nicht scrollenden `UITextView` auf die Höhe der View; `InkNoteTextView.layoutSubviews` hebt das wieder auf, sonst wird nach einem Zusammenführen die letzte Zeile abgeschnitten. Test `BlockEditingTests.testMeasuringLeavesTheContainerAlone`.

## P-038 · Tastatur weiß nichts von Änderungen am Textspeicher

**Symptom.** Auf dem iPad landen getippte Zeichen an falscher Stelle, Wörter werden zerhackt oder Autokorrektur ersetzt fremden Text, sobald der Editor selbst etwas umbaut (Return, Block-Kürzel, Stil).
**Ursache.** Direkte Änderungen an `textStorage` gehen am Eingabesystem vorbei; dessen Puffer hält noch den alten Text. Ein selbst eingefügter Zeilenumbruch verschiebt alles Folgende.
**Wache.** Return fügt das Textfeld selbst ein; der Editor setzt danach nur die Stile (`EditorEngine.finishNewline`). Jede eigene Änderung läuft durch `performEdit`, das auf dem iPad `inputDelegate.textWillChange/textDidChange` meldet, und jede eigene Auswahl durch `selectionWillChange/selectionDidChange`. Kein automatischer Test für das Eingabesystem; die Testumgebung tippt ohne Tastatur-Puffer. Prüfen: im Simulator „a, Return, b“ zügig tippen.

## P-039 · Textfeld mit eigenem Container hält den Textspeicher nicht

**Symptom.** Absturz beim Öffnen einer Textnotiz: „text container must already have a layout manager“.
**Ursache.** Ein `UITextView`/`NSTextView`, das mit eigenem `NSTextContainer` erzeugt wird, hält den `NSTextStorage` oben im Stapel nicht. Freigegeben, nimmt er den Layout-Manager mit.
**Wache.** `InkNoteTextView.ownedStorage` hält den Speicher, solange das Textfeld lebt.

## P-040 · Getippter Text verliert den Absatzstil

**Symptom.** Auf dem iPad wird nach Return in einer Liste oder Aufgabe der nächste Punkt zu normalem Text.
**Ursache.** `UITextView` gibt eigene Attribute (`inkhash.blockType`) aus den Tippattributen nicht zuverlässig an neue Zeichen weiter. Der Stil eines Absatzes wurde aus seinem ersten Zeichen gelesen, und das hatte keinen.
**Wache.** `EditorEngine.style(of:)` nimmt das erste Zeichen, das einen Stil trägt; ein letzter Absatz ohne solches nimmt den Stil der leeren Zeile (`trailing`). `restyle` schreibt ihn danach auf den ganzen Absatz. Test `BlockEditingTests.testReturnContinuesListsAndTasks`.

## P-041 · Return per Tastenbefehl läuft am Delegate vorbei

**Symptom.** Mit Hardware-Tastatur setzt Return keine Liste fort; im Simulator landen Zeilenumbrüche mitten im Wort.
**Ursache.** Der Tastenbefehl aus P-029 fügt `\n` mit `insertText` ein. Das ruft `shouldChangeTextIn` nicht auf, die Regeln für Return liefen nicht. Im Simulator überholen getippte Zeichen den Tastenbefehl.
**Wache.** `InkNoteTextView.returnPressed` ruft `EditorEngine.returnKey`, das die Regeln selbst anwendet und den Umbruch danach einfügt.

## P-042 · PencilKit zeigt sein Menü über den Seitenwerkzeugen

**Symptom.** Mit Auswahl, Form oder Tape erscheint beim Tippen „Alles auswählen / Platz einfügen“ von PencilKit.
**Ursache.** `PKCanvasView` hat eigene Tipp-Gesten, die neben unseren laufen.
**Wache.** `InkPageCanvas.Coordinator.gestureRecognizer(_:shouldBeRequiredToFailBy:)` lässt alle Gesten der Zeichenfläche außer Scrollen und Zoomen auf unsere warten.

## P-043 · Erkennung überschreibt sich selbst oder sieht weiße Tinte

**Symptom.** Nach dem Schreiben fehlt die letzte Zeile in Abschrift und Schlagwörtern, oder auf einem Gerät im Dunkelmodus wird gar nichts erkannt.
**Ursache.** Jeder Strich startete eine Erkennung; eine ältere, langsamere schrieb ihr Ergebnis nach der neueren. Und `PKDrawing.image` zeichnet Tinte für die aktuelle Darstellung, im Dunkelmodus hell auf durchsichtig.
**Wache.** `InkNoteView.recognize` wartet 0,9 s Schreibpause und schreibt nur, wenn keine neuere Anfrage für die Seite kam. `HandwritingRecognizer.rendered` zeichnet die ganze Seite im hellen Modus. Zugeschnitten oder auf Weiß las Vision im Test schlechter.

## P-044 · Linkfläche ohne Schema blockiert den Abgleich

**Symptom.** Nach dem Verlinken einer Auswahl in der Handschrift mit `example.com` gleicht die Notiz nicht mehr ab; der Server antwortet 400 `bad-request`, `reason: "element"`.
**Ursache.** Das Linkfeld speicherte die Eingabe, wie sie war; „ohne Schema `https://` voranstellen“ passierte erst beim Öffnen. Der Server nimmt nur `https://`, `http://`, `mailto:` und `inkhash://note/` an. Ein Titel mit Leerzeichen, der keine Notiz traf, landete ebenso als Ziel.
**Wache.** `LinkTarget.normalize` vor jedem Speichern, `LinkTarget.repaired` beim Lesen einer Seite. `LinkTargetTests`, `SyncTests.testStoredLinksWithoutSchemeAreRepaired`.

## P-045 · Eine abgelehnte Notiz hält den ganzen Abgleich an

**Symptom.** Der Status zeigt bei jedem Abgleich „Der Server antwortete mit 400.“; Änderungen an anderen Notizen kommen nie auf den Server.
**Ursache.** `Syncer.sync` fing beim Hochladen nur `409` ab. Jede Ablehnung (400 wegen einer Grenze, 413 wegen der Größe) brach den Lauf ab, vor den übrigen Notizen und vor dem zweiten Holen. Die Notiz blieb ungesendet und stand beim nächsten Mal wieder vorn.
**Wache.** `Syncer.sync` sammelt 400 und 413 pro Notiz in `SyncReport.rejected` und macht weiter; `SyncCoordinator.describe` nennt die Notiz. Die App hält die Grenzen aus API.md selbst ein (`Limits`). Test `SyncTests.testRejectedNoteDoesNotBlockOthers`.

## P-046 · Mac-Icon ist nicht das Logo

**Symptom.** Auf iOS stimmt das App-Icon, auf dem Mac zeigen Dock und Finder ein verkleinertes `#` auf einer grauen Platte oder ein fremd wirkendes Quadrat.
**Ursache.** macOS maskiert App-Icons nicht. Ein randloses Quadrat wie für iOS gilt seit macOS 26 als nicht passend und wird auf eine Standardplatte gesetzt. Im Katalog stand für den Mac zudem nur 512@2x.
**Wache.** `make icon` rendert mit `--mac` eine eigene Platte auf Apples Raster (824 von 1024, Radius 185, Schatten) in allen Mac-Größen (`AppIcon-mac-*.png`). Die iOS-Datei `AppIcon.png` bleibt das volle Quadrat. Kein automatischer Test; nach `make icon` die Renditions mit `xcrun assetutil --info …/Assets.car` prüfen.

## P-047 · „lese Handschrift…“ hört nicht auf

**Symptom.** In einer Handschriftnotiz steht dauerhaft „lese Handschrift…“, auch ohne zu schreiben.
**Ursache.** Das Laden einer Zeichnung in den Canvas löste `canvasViewDrawingDidChange` aus wie ein Strich: Die Seite wurde gespeichert und neu erkannt, die Erkennung änderte die Notiz, die Ansicht lud die Zeichnung erneut. Zusätzlich blieb die Anzeige stehen, wenn eine Erkennung für eine andere Seite die Markierung überschrieben hatte.
**Wache.** `Coordinator.load` setzt `settingDrawing`. `onDrawing` erkennt nur, wenn `NoteLibrary.updateDrawing` eine Änderung meldet. `readingPages` ist eine Menge, die die neueste Anfrage einer Seite in jedem Fall räumt. Kein automatischer Test; im Gerät prüfen.

## P-048 · Hinter dem Proxy sind alle ein Client

**Symptom.** Hinter Caddy, nginx oder `tailscale serve` kann sich 15 Minuten lang niemand anmelden, obwohl nur einer falsch getippt oder geraten hat. Oder nginx antwortet bei Zeichnungen mit 413.
**Ursache.** Der Server sieht nur die Adresse des Proxys, alle Fehlversuche landen in einem Zähler. nginx nimmt standardmäßig höchstens 1 MB an, Blobs haben bis zu 20 MiB.
**Wache.** ADR 0038: `INKHASH_TRUSTED_PROXIES` und `clientAddress` in `Server/inkhashd.ts`, Test „a trusted proxy names the client, others share the proxy's counter“. Der Server meldet einmal im Log, wenn ein nicht vertrauter Absender `X-Forwarded-For` schickt. Für nginx `client_max_body_size 25m` und `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for`.

## P-049 · Docker öffnet Ports an der Firewall vorbei

**Symptom.** ufw oder firewalld blockt 8787, trotzdem ist der Server aus dem Internet oder dem ganzen Netz erreichbar, über reines HTTP.
**Ursache.** Docker schreibt eigene iptables-Regeln für veröffentlichte Ports, vor denen der Firewall.
**Wache.** `deploy/docker/compose.yaml` bindet `${INKHASH_BIND:-127.0.0.1}`. Nur fürs Heimnetz `0.0.0.0` setzen, nie zusammen mit einer Portfreigabe im Router. Kein automatischer Test.

## P-050 · PDF-Seite als Bild bleibt winzig

**Symptom.** Eine importierte PDF-Seite erscheint als kleines Bild in der Mitte eines leeren Rechtecks.
**Ursache.** `CGPDFPage.getDrawingTransform` verkleinert nur, es vergrößert nie. Wer eine Seite in mehr Pixel rendert, als sie Punkte hat, bekommt sie in Originalgröße, zentriert.
**Wache.** `InkImport.fill(_:with:)` rechnet die Transformation selbst, inklusive `/Rotate`. Kein automatischer Test, die App hat für den Import keinen; mit `make import-spike FILE=…goodnotes` prüfen.

## P-051 · GoodNotes-Datei: Fallen im Format

**Symptom.** Seiten in falscher Reihenfolge, gelöschte Seiten tauchen auf, Striche sind schwarz statt blau oder verschoben, eine Seite hat das falsche Papier.
**Ursache.** Fünf Dinge, siehe ADR 0041. `index.notes.pb` ist nicht die Reihenfolge; die steht in den Schlüsseln der Ereignisse `#54`/`#55`, bytewise verglichen. Die Notizschicht hat die UUID der Seite plus eins mit Übertrag (`…000F` → `…0010`); ein Vergleich nur der letzten Ziffer findet diese Seiten nicht. Protobuf lässt Farbanteile weg, die null sind; der Standard ist 0, nicht 1. Ein Strich, der mit dem Lasso verschoben wurde, trägt den Versatz in `#6` und nicht in den Punkten. Ereignis `#3` bindet eine Seite an ein anderes Papier; das letzte gewinnt.
**Wache.** `GoodNotesTests.testOrdersPagesByKeyDropsDeletedPagesAndScales` und `testPageUUIDCarries`. Breiten und Farben der PencilKit-Tinten sind gemessen und mit GoodNotes' eigenem PDF-Export verglichen (`InkImport.pkStroke`); dafür gibt es keinen Test, nur `make import-spike`.

## P-052 · Papiermuster als eine große Ebene

**Symptom.** Speicher läuft voll oder die App wird beendet, sobald eine lange Handnotiz Linien oder Punkte hat. Oder sie stürzt beim Zeichnen des Musters ab.
**Ursache.** Eine Ebene über die ganze Seite hält ein Bitmap von Seitenhöhe mal Zoom mal Bildschirmskala, bei 10 000 Punkten mehrere hundert MB. `CATiledLayer` zeichnet in Hintergrund-Threads, und unter Swift 6 ist `draw(_:)` einer `UIView` an den Main Actor gebunden.
**Wache.** `PaperPatternView` deckt nur `canvas.bounds` und wird in `scrollViewDidScroll` neu gesetzt (`Coordinator.layoutPaper`). Nach jedem Update setzt `layoutLayers` sie einen Takt später noch einmal: SwiftUI ruft `updateUIView` mitunter, bevor die Zeichenfläche ihre Größe hat, und das Muster blieb dann bis zum ersten Scrollen unsichtbar. Kein automatischer Test; im Gerät eine lange Seite mit Punkten scrollen.

## P-053 · Eigener Push wird zum Konflikt

**Symptom.** Wer zügig zeichnet oder tippt, bekommt auf einem einzigen Gerät „Konflikt mit dem Server“. Selten verschwindet auch eine Eingabe, die während des Abgleichs kam.
**Ursache.** Drei Rennen gegen den eigenen Schreibvorgang. `scheduleSync` (heute `SyncCoordinator.schedule`) brach mit jeder Eingabe die laufende Task ab, auch mitten im PUT; der Server speicherte, das Gerät bekam die neue Revision nie. `Syncer` speicherte nach dem PUT die hochgeladene Fassung als sauber, auch wenn inzwischen eine neuere im Speicher lag. Und das AppModel bearbeitet seine `records`, die erst `reload` am Ende des Abgleichs nachlud; eine Eingabe dazwischen schrieb die alte Revision zurück.
**Wache.** `SyncCoordinator.schedule` bricht nur das Warten ab; `sync` läuft danach noch einmal, statt einen Aufruf zu verwerfen. `Syncer` liest jede Notiz vor dem Push neu, setzt eine zwischendurch geänderte nach der Antwort auf die Revision des Servers und lässt sie dirty (`Writer.saveAfterPush`), und meldet jeden Speichervorgang sofort über `onSave`, womit `NoteLibrary.synced` die `records` nachführt. Tests `SyncTests.testEditDuringPushStaysDirtyOnTheServerRevision`, `testEditAfterOwnPushIsNoConflict`, `testEditDuringPushOfAnotherNoteGoesUpFresh`. Bleibt offen: Reißt die Verbindung mitten im PUT ab und wird danach weitergeschrieben, ist es weiter ein Konflikt.

## P-054 · Bestätigungsdialog zeigt ins Leere

**Symptom.** Auf dem iPad zeigt die Sprechblase von „Notiz löschen?“, „Server entfernen?“ und ähnlichen Dialogen auf die Mitte der Seitenleiste oder des Formulars, nicht auf die Zeile oder den Knopf, der sie geöffnet hat.
**Ursache.** `confirmationDialog` wird auf regulärer Breite ein Popover und zeigt auf die View, an der der Modifier hängt. Hängt er am ganzen Container, zeigt er auf dessen Mitte.
**Wache.** Jeden `confirmationDialog` an die auslösende Zeile oder den Knopf hängen. Bei Listen bindet `isPresented` an die ID der Zeile (`pendingDelete == id`). Kein automatischer Test; auf dem iPad ausprobieren.

## P-055 · Importiertes Notizbuch friert die App ein

**Symptom.** Nach dem Import eines GoodNotes-Notizbuchs steht dauerhaft „lese Handschrift…“, die App reagiert kaum, die Suche findet nichts. iPad und iPhone.
**Ursache.** Beim Öffnen startet für jede ungelesene Seite eine Erkennung. `PKDrawing.image` und Vision blockieren ihren Thread synchron, liefen aber auf dem kooperativen Pool von Swift Concurrency. Bei zehn Seiten waren alle Threads des Pools belegt und warteten aufeinander (PencilKit-Metal, Vision-Queue): Deadlock, danach lief keine Task der App mehr.
**Wache.** `HandwritingRecognizer` rendert und liest nur auf seiner eigenen seriellen `DispatchQueue`, eine Seite nach der anderen, und kehrt per Continuation zurück. Blockierende Framework-Aufrufe nie in `Task`/`Task.detached` direkt ausführen. Kein automatischer Test; im Simulator mit einem Notizbuch mit vielen Seiten prüfen.

## P-056 · Geisterzeilen im Ordnerbaum

**Symptom.** Auf dem Mac stehen in der Seitenleiste Notizen, die dort nicht hingehören: nach dem Wechsel in einen leeren Workspace unter „Noch keine Notizen.“, oder eine Zeile liegt über einem Ordner und beide Titel überlagern sich. Ein Neustart behebt es; die Daten sind heil.
**Ursache.** Der Baum war aus verschachtelten `DisclosureGroup`s in einer `List` gebaut. Auf macOS steckt dahinter ein `NSOutlineView`, und wenn sich die Kinder eines aufgeklappten Ordners zusammen mit der übrigen Struktur ändern (Workspace-Wechsel, Notiz in anderen Ordner, neue Notiz), entfernt SwiftUI alte Zeilen nicht immer.
**Wache.** `NoteTree.rows(isExpanded:)` macht den Baum zu flachen Zeilen mit Tiefe; die Seitenleiste zeichnet sie in einem einzigen `ForEach` und klappt Ordner selbst auf. Test `NoteListingTests.testTreeRowsAreFlatAndSkipCollapsedFolders`. Keine verschachtelten `DisclosureGroup`s oder `OutlineGroup`s in der Seitenleiste.

## P-057 · Tippen löst den Konflikt still auf

**Symptom.** In einer Textnotiz mit Konflikt verschwindet der Hinweis, sobald man tippt. Beim nächsten Abgleich kommt er wieder, und die Fassung des Servers war zwischendurch nicht mehr zu sehen.
**Ursache.** `NoteLibrary.updateMarkdown` setzte `conflict = false` und löschte die gespeicherte Fassung des Servers, ohne die Revision des Servers zu übernehmen. Der nächste PUT lief mit der alten `baseRevision` wieder in 409.
**Wache.** Text geht wie jede andere Änderung durch `NoteLibrary.change`, das den Konflikt stehen lässt. Gelöst wird nur über `resolveConflict` (ADR 0049). Test `NoteLibraryTests.testTypingKeepsTheConflict`.

## P-058 · Zwei Seiten, ein Vertrag, kein gemeinsamer Test

**Symptom.** Server-Tests und Swift-Tests sind grün, trotzdem lehnt der Server, was die App schickt, oder die App versteht seine Antwort nicht. Bei verschlüsselten Notizen fällt das erst auf einem zweiten Gerät auf.
**Ursache.** Jede Seite testete gegen ihr eigenes Bild des Vertrags: der Server mit JSON von Hand, die App mit einem Fake-Transport.
**Wache.** `make test` startet den echten Server auf einem freien Port und lässt `ContractTests` mit `APIClient`, `SealedTransport` und `SealedLooks` dagegen laufen (`tools/contract-test.sh`): Umstieg auf den Tresor, zweites Gerät, Konflikt, Retry, Bild, Wiederherstellungsschlüssel, Kopplung, Reset. Neue Routen bekommen dort einen Fall.

## P-059 · Code-Block per Kürzel kommt nie an

**Symptom.** „```“ und Leerzeichen am Zeilenanfang macht keinen Code-Block. Die Backticks verschwinden oder bleiben als Text stehen.
**Ursache.** Nach jedem Zeichen liest der Editor die Zeile als Inline-Markdown neu (`reconcileInline`). Zwei Backticks sind dort leerer Inline-Code und wurden entfernt, bevor der dritte und das Leerzeichen das Block-Kürzel (`BlockShortcut`) erreichen konnten.
**Wache.** `EditorEngine.reconcileInline` lässt einen Absatz in Ruhe, der nur aus ein bis drei Backticks besteht. Test `BlockEditingTests.testCodeBlockKeepsItsLines`.

## P-060 · UIKit wirft seinen Verlauf weg, sobald der Editor Text ändert

**Symptom.** Im Text auf iPad und iPhone geht Rückgängig nur bis zur letzten Formatierung, zum letzten Kürzel oder zur letzten Tabellenzelle. Davor Getipptes lässt sich nicht mehr zurücknehmen.
**Ursache.** Der `UndoManager` von `UITextView` (`_UITextUndoManager`) löscht seine Tipp-Schritte, sobald sich die Zeichen im Text ändern, ohne dass er es selbst war: ein ersetzter Bereich genügt, nur Attribute nicht. Die `EditorEngine` ändert den Text direkt im `NSTextStorage`. Früher wurde der Verlauf deshalb nach jeder solchen Änderung ganz gelöscht.
**Wache.** `InkNoteTextView` auf iOS gibt einen eigenen `UndoManager` aus und legt alle Schritte selbst an: einen pro Lauf beim Tippen (`recordTyping`) und einen pro Änderung der Engine (`performEdit`). Jeder Schritt legt den ganzen Text samt Auswahl zurück (`EditorEngine.snapshot`/`restore`, ADR 0059). In den `UndoManager` von UIKit nichts eintragen und ihn nicht mit eigenen Schritten mischen. Tests in `UndoTests`.

## P-061 · Menüs im Text stehen nicht am Cursor

**Symptom.** Das `/`-Menü, das `[[`-Menü oder der Link-Chip öffnen sich weit rechts oder unter dem Cursor, nicht an ihm. Am Zeilenanfang fällt es kaum auf.
**Ursache.** Zwei Dinge. `EditorEngine` meldete als Cursor den ganzen Zeilenkasten: Zeilenanfang statt Einfügemarke, mit Absatz- und Zeilenabstand. Und die Menüs lagen direkt im `overlay` des Textfelds; SwiftUI zentrierte einige von ihnen in der Breite, bevor der `offset` wirkte.
**Wache.** `EditorEngine.caretRect` liefert die Einfügemarke in Schrifthöhe (Test `EditorLookTests.testTheCaretIsWhereTheCursorStandsNotAtTheLineStart`). `TextNoteView` legt alle Menüs in ein eigenes `ZStack(alignment: .topLeading)` mit voller Größe. `make mac-test` rendert das Blatt mit offenem Menü nach `/tmp/inkhash-mac-sheet.png`.

## P-062 · Tippen wirft die Notiz nach oben

**Symptom.** In einer langen Textnotiz springt die Ansicht beim Tippen oder beim Öffnen des `/`-Menüs ein Stück oder ganz nach oben; der Cursor ist danach außer Sicht.
**Ursache.** `TextNoteView` scrollte bei jeder Änderung des Cursors per `ScrollViewReader.scrollTo` zu einer unsichtbaren Markierung über dem Text. Die Markierung stand per `offset` am Cursor; `offset` verschiebt nur das Bild, `scrollTo` geht nach der Lage, also oben links. Auch mit `padding` rechnete SwiftUI die Stelle falsch.
**Wache.** Kein `scrollTo` für den Cursor. Die Engine ruft `EditorHost.reveal` mit der Einfügemarke, nur wenn sich Auswahl oder Text geändert haben; das Textfeld scrollt die umgebende Scroll-Ansicht selbst, nur so weit wie nötig (`scrollToVisible`, `scrollRectToVisible`). Tests `MacNoteSheetTests.testTheSlashMenuKeepsTheNoteWhereItIs` und `testTypingOutOfSightScrollsToTheCursor` (`make mac-test`).

## P-063 · Rückgängig gehört zur Seite und zur Notiz, nicht zum Fenster

**Symptom.** Auf dem iPad: Strich auf Seite 1, umblättern, Rückgängig; Seite 2 bekommt die Tinte von Seite 1 und verliert ihre eigene. Auf dem Mac: nach dem Wechsel in eine andere Notiz ist ↶ aktiv und ändert unsichtbar die geschlossene Notiz, der Verlauf hält beliebig viele volle Kopien der Zeichnung.
**Ursache.** Der `PKCanvasView` bleibt beim Blättern derselbe, sein `UndoManager` mit ihm. Auf dem Mac ist `@Environment(\.undoManager)` der Manager des Fensters; `NSTextView` benutzt ebenfalls den des Fensters. Seit ADR 0059 sind diese Schritte über Knöpfe sichtbar und erreichbar.
**Wache.** `InkPageCanvas.updateUIView` leert den Manager des Canvas beim Seitenwechsel. Auf dem Mac nimmt die Zeichenfläche ihre Schritte beim Verschwinden zurück (`removeAllActions(withTarget: history)`), das Textfeld beim Abbau (`dismantleNSView`); beide setzen `levelsOfUndo = 100`. Test `InkPageCanvasTests.testTurningThePageDropsTheUndoStepsOfTheOldOne`.

## P-064 · `/`-Menü am Dokumentende abgeschnitten

**Symptom.** Steht der Cursor in den letzten Zeilen einer Textnotiz, zeigt das `/`-Menü (oder `[[`) nur seine oberen Einträge; der Rest lässt sich nicht hinscrollen.
**Ursache.** Das Menü hängt als Overlay unter der Cursorzeile und vergrößert den Inhalt der `ScrollView` nicht. Der Leerraum nach dem Text war fest 240 pt, das volle Menü ist rund 470 pt hoch, und gescrollt wurde nur bis zum Cursor.
**Wache.** `TextNoteView` misst Text und offenes Menü, lässt den Leerraum bis unter das Menü wachsen, sodass sich das ganze Menü hinscrollen lässt. Automatisch gescrollt wird nur bis zum Cursor, durch das Textfeld selbst: Ein Scroll-Proxy von SwiftUI warf die Notiz nach oben (P-062). Das Menü bleibt unter der Cursorzeile (P-010). Kein automatischer Test; in einer langen Notiz in der letzten Zeile `/` tippen, auf Mac, iPad und iPhone.

## P-065 · Gemalte Kästchen aus mehreren Strichen

**Symptom.** Eine Aufgabenliste in Handschrift mit gemalten Kästchen erscheint nicht in der Aufgabenliste; die Abschrift beginnt die Zeilen mit „I“ oder „1“.
**Ursache.** `TaskBoxes` nahm nur Kästchen aus einem geschlossenen Strich. Auf dem iPad gezeichnet bestehen sie oft aus einem „∩“ und dem Boden, deren Enden über die Ecken hinausstehen. Nach dem Umriss der Striche gemessen ist so ein Kästchen oben so rund wie ein O.
**Wache.** Mehrere Striche nacheinander bilden ein Kästchen über die eingeschlossene Fläche (`EnclosedArea`) und eine gerade, waagrechte Linie oben oder unten (ADR 0065). Test `TaskBoxTests.testTheBoxesOfAWrittenPageAreFound` mit den echten Strichen einer iPad-Seite aus `docs/fixtures/ink-task-boxes.json`.


## P-066 · Ein Sheet an einer `Section` geht dreimal auf

**Symptom.** Auf dem iPhone: Tresor-Abfrage mit „Später“ weggeschoben, dann in den Einstellungen des Servers „Tresor öffnen…“. Das Fenster erscheint kurz, dann schließen sich Tresor und Einstellungen zusammen, bevor man den Schlüssel eingeben kann.
**Ursache.** `VaultSection` hing `.sheet` und `.task` an die `Section`. In einer `Form` gibt SwiftUI die Modifier einer `Section` an jede Zeile, an Kopf und Fuß weiter: Ein Tipp präsentierte dasselbe Sheet dreimal, UIKit nahm das zurück und die Einstellungen mit. Die Prüfung des Tresors lief ebenso dreimal.
**Wache.** Sheets hängen an ihrem Knopf, nie an einer `Section`; „Tresor anlegen…“ und „Tresor öffnen…“ sind ein Knopf, damit das Zurücksetzen (needsKey → needsSetup) das offene Sheet nicht abbaut. Die Prüfung macht `ServerDetailView`. Test `VaultUITests.testOpenVaultFromSettingsAfterPostponing` im iPhone-Simulator gegen Kennels Testserver (`make ui-test`).
