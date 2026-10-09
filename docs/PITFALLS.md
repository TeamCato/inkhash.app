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
**Wache.** `ServerSessions.expire(_:ifStill:)` läuft nur bei `sync` und `remoteWorkspaces`, nicht beim Anmelden. Die Sitzung gilt pro Server. Es vergleicht den Token vom Start der Anfrage mit dem aktuellen. Die Bibliothek bleibt gebunden, `ExpiredSessionBanner` bietet das Anmelden an. Kein automatischer Test, weil die App kein Testziel hat. Prüfen: Sitzungsdatei auf dem Server löschen, dann abgleichen.

## P-028 · Block-Kürzel lassen das Zeichen stehen

**Symptom.** `# hallo` wird zur Überschrift `#hallo`, gespeichert als `# #hallo`.
**Ursache.** Nach dem Leerzeichen wechselte nur der Blocktyp im Modell. Das Textfeld behielt das `#`, bis SwiftUI den leeren Block zurückschob, und schnelles Tippen landete dahinter.
**Wache.** `EditorEngine.applyShortcut` löscht das Kürzel im selben Aufruf, in dem es erkannt wird, und setzt den Stil des Absatzes. Nach einem geschlossenen Inline-Marker (`*x*`, `**x**`, `` `x` ``) gehen die Tippattribute auf normal zurück. Kein automatischer Test, die App hat kein Testziel.

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
**Wache.** `IOSNoteText` und `MacNoteText` implementieren `sizeThatFits`: Sie nehmen die angebotene Breite und messen die Höhe über `EditorEngine.height(for:)`, siehe P-037. Kein automatischer Test, die App hat kein Testziel. Prüfen: lange Zeile im iPad-Hochformat mit offener Liste.

## P-034 · Zeichnung landet auf der falschen Seite

**Symptom.** Was man auf einer Handschriftseite schreibt, erscheint nach dem Blättern auf der falschen Seite, oder eine Seite zeigt ihre eigenen Striche nicht.
**Ursache.** Zwei Dinge. Die Zeichenfläche speichert verzögert (0,45 s), und der verzögerte Auftrag fragte beim Ausführen nach der gerade gezeigten Seite, nicht nach der, auf der gezeichnet wurde. Und `PKCanvasView` malt eine Zeichnung nicht, die es bekam, bevor Größe und Zoom feststanden.
**Wache.** `InkPageCanvas.Coordinator` merkt sich seine `pageID` und gibt sie bei jedem Speichern mit. Wechselt die Seite oder verschwindet die Fläche, wird Ausstehendes zuerst für die alte Seite gesichert (`flush`). Nach dem Anlegen und nach jeder Zoom-Änderung gibt `redrawSoon` die Zeichnung noch einmal herein. Kein automatischer Test, die App hat kein Testziel. Prüfen: auf Seite 1 schreiben, sofort blättern, auf Seite 2 schreiben, zurück.

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
**Wache.** `EditorEngine.height(for:)` misst nur dann am echten Layout, wenn dessen Container genau so breit ist wie gefragt und nicht in der Höhe begrenzt; sonst auf einem eigenen `NSLayoutManager`. UIKit setzt den Container eines nicht scrollenden `UITextView` auf die Höhe der View; `InkNoteTextView.layoutSubviews` hebt das wieder auf, sonst wird nach einem Zusammenführen die letzte Zeile abgeschnitten. Kein automatischer Test, die App hat kein Testziel.

## P-038 · Tastatur weiß nichts von Änderungen am Textspeicher

**Symptom.** Auf dem iPad landen getippte Zeichen an falscher Stelle, Wörter werden zerhackt oder Autokorrektur ersetzt fremden Text, sobald der Editor selbst etwas umbaut (Return, Block-Kürzel, Stil).
**Ursache.** Direkte Änderungen an `textStorage` gehen am Eingabesystem vorbei; dessen Puffer hält noch den alten Text. Ein selbst eingefügter Zeilenumbruch verschiebt alles Folgende.
**Wache.** Return fügt das Textfeld selbst ein; der Editor setzt danach nur die Stile (`EditorEngine.finishNewline`). Jede eigene Änderung läuft durch `performEdit`, das auf dem iPad `inputDelegate.textWillChange/textDidChange` meldet, und jede eigene Auswahl durch `selectionWillChange/selectionDidChange`. Kein automatischer Test, die App hat kein Testziel. Prüfen: im Simulator „a, Return, b“ zügig tippen.

## P-039 · Textfeld mit eigenem Container hält den Textspeicher nicht

**Symptom.** Absturz beim Öffnen einer Textnotiz: „text container must already have a layout manager“.
**Ursache.** Ein `UITextView`/`NSTextView`, das mit eigenem `NSTextContainer` erzeugt wird, hält den `NSTextStorage` oben im Stapel nicht. Freigegeben, nimmt er den Layout-Manager mit.
**Wache.** `InkNoteTextView.ownedStorage` hält den Speicher, solange das Textfeld lebt.

## P-040 · Getippter Text verliert den Absatzstil

**Symptom.** Auf dem iPad wird nach Return in einer Liste oder Aufgabe der nächste Punkt zu normalem Text.
**Ursache.** `UITextView` gibt eigene Attribute (`inkhash.blockType`) aus den Tippattributen nicht zuverlässig an neue Zeichen weiter. Der Stil eines Absatzes wurde aus seinem ersten Zeichen gelesen, und das hatte keinen.
**Wache.** `EditorEngine.style(of:)` nimmt das erste Zeichen, das einen Stil trägt; ein letzter Absatz ohne solches nimmt den Stil der leeren Zeile (`trailing`). `restyle` schreibt ihn danach auf den ganzen Absatz. Kein automatischer Test, die App hat kein Testziel.

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
