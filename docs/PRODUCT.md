# Produkt

inkhash ist eine schlanke Notiz-App für iPad, iPhone und macOS. Auf dem iPad schreibt man mit dem Stift, auf dem Mac in einem Editor, der Markdown sofort in Formatierung verwandelt. Die Notizen liegen auf dem Gerät. Wer will, gleicht sie über einen Server ab, den man selbst betreibt.

## Warum es inkhash gibt

Es gab keine Notiz-App, die alles zugleich kann. Sie soll sich selbst betreiben lassen. Sie soll auf einem Firmenrechner laufen, auf dem es kein iCloud gibt. Und sie soll auf den Geräten gehen, die man gerade zur Hand hat: am Laptop Text tippen, auf dem iPad mit dem Stift schreiben, beides in derselben Bibliothek. Deshalb gleicht inkhash über einen eigenen Server ab und setzt kein iCloud voraus.

Mehr soll es nicht sein. Keine Datenbanken, keine Whiteboards, kein Assistent. Einfache Tabellen im Text gibt es (ADR 0027, 0036).

## Zwei Arten zu schreiben

Eine Notiz ist entweder Handschrift (`ink`) oder Text (`text`).

Handschrift ist für das iPad mit Apple Pencil gedacht: Seiten, Stift, Radierer, ein ruhiges Blatt. Am linken Rand liegt eine Papierleiste, immer ganz offen: Füller, Stift, Strich, Marker, Radierer, Form, Tape, Bild, Auswahl, darunter Farben, eine eigene Farbe und die Stärke. Fotos bekommen Rahmen und Masken, Formen und Tape liegen unter der Tinte. Mit der Auswahl verschiebt man, vergrößert, löscht und verlinkt, auch Handschrift, auf eine Adresse oder eine andere Notiz (ADR 0028). Der Finger zeichnet auf dem iPad nur, wenn man ihn einschaltet. Klebezettel gibt es nicht. Der Anspruch ist nicht, GoodNotes nachzubauen, sondern dass sich Schreiben nicht nach einem Kompromiss anfühlt. Auf dem Mac werden die Seiten gezeigt und durchsucht; mit der Maus macht man kleine Änderungen oder skizziert grob, etwa einen neuen Ausschnitt in einer Textnotiz, den man später auf dem iPad schön nachzeichnet (ADR 0058). Bilder, Formen und Auswahl bleiben beim iPad.

Text ist für den Mac gedacht, funktioniert aber überall.

Das iPhone ist zum Nachlesen und für Kurzes da: Notiz öffnen, etwas tippen, eine Aufgabe abhaken. Handschrift lässt sich dort lesen und mit dem Finger ergänzen (ADR 0026).
 Man schreibt Markdown und liest es nicht. `# ` am Zeilenanfang wird eine Überschrift, `**` wird fett, `*` kursiv. Mit `/` öffnet sich ein Menü für Überschriften, Listen, Aufgaben, Tabellen, Code und Links; „Link“ fragt direkt nach Ziel und Text (ADR 0031). Mitten im Text geht das auch, dann ohne Überschriften, Code-Block und Tabelle (ADR 0033). `x ` am Zeilenanfang macht eine Aufgabe, `| a | b |` und Return eine Tabelle, `[[` verlinkt eine andere Notiz (ADR 0027). Ausschnitte zeigen einen Teil einer anderen Notiz: im Text über `/Ausschnitt`, auf der Handschriftseite über das Bild-Menü, aus Handschrift wie aus Text. Bei Handschrift zieht man ein Rechteck auf, bei Text tippt man den ersten und den letzten Absatz an. Man kann im selben Dialog auch eine neue Notiz schreiben; sie liegt dann unter der Notiz, aus der sie kommt, und bekommt ihren Titel aus dem Inhalt. Ein Ausschnitt ist immer ein Fenster auf die andere Notiz, keine Kopie (ADR 0032, 0035, 0037). Tabellen lassen sich über einen Knopf am Rand ausrichten, in der Breite ändern, mit oder ohne Kopfzeile und mit Zebrastreifen zeigen (ADR 0036). Links zeigen in Text und Handschrift auf andere Notizen oder nach außen, auf Web- und E-Mail-Adressen. Markierter Text bekommt eine kleine Leiste mit Fett, Kursiv, Unterstrichen, Durchgestrichen, Textmarker, Code, Link und „In Aufzählung umwandeln“ (ADR 0079), sonst bleibt die Fläche ohne Werkzeugleiste.

Die Fläche ist hell: ein Blatt Papier auf einem hellen Schreibtisch. Was darüber schwebt, Suche, Leisten und Menüs, ist ebenfalls Papier mit feiner Kante und weichem Schatten, wie auf der Website (ADR 0029).

`# Titel` mit Leerzeichen ist eine Überschrift. `#wort` ohne Leerzeichen ist ein Schlagwort. Das gilt im Text. In der Handschrift gilt auch `# wort` mit Leerzeichen als Schlagwort, weil der Abstand beim Schreiben nicht die Überschrift meint.

## Workspaces, Ordner, Schlagwörter

Notizen liegen in Workspaces, etwa Privat und Arbeit. Alles, was man sieht, gehört zum gerade gewählten Workspace: Notizen, Ordner, Schlagwörter, Suche. In einem Workspace sagen Ordner, wo etwas liegt, und Schlagwörter, womit es zusammenhängt. Eine Notiz trägt einen Pfad wie „Projekt / Treffen / Thema“ und beliebig viele Schlagwörter; der Pfad steht mit dem Titel oben auf dem Blatt. Die Seitenleiste ist der Baum daraus, Notizen als Blätter. Tippt man `#schlagwort` in die Suche, bleibt der Baum stehen und zeigt nur noch die Notizen mit diesem Schlagwort (ADR 0022). Dazu gibt es Favoriten und einen Papierkorb, aus dem man zurückholen kann. Ein dritter Knopf unten zeigt alle Aufgaben des Workspace auf einem Blatt, aus Text und Handschrift, nach Fälligkeit; dort hakt man sie ab, ohne die Notiz zu öffnen. Im Text bekommt eine Aufgabe auf Wunsch ein Datum (`📅 2026-10-20` am Zeilenende), in der Handschrift ist ein gemaltes Kästchen vor einer Zeile eine Aufgabe (ADR 0060). Auf dem iPad füllt eine geöffnete Notiz den Bildschirm; die Seitenleiste holt man über den Knopf oben links zurück (ADR 0030).

Kennel verbindet man einmal, über „Mit Kennel verbinden“ (Finden › Anmelden › Übernehmen); die App kennt genau einen Kennel. Jeder Workspace liegt „Nur hier“ oder ist „Abgeglichen“ mit einem Workspace in Kennel; die Marke steht in der Workspace-Wahl. Ein Account kann mehrere Workspaces abgleichen. Siehe ADR 0020 und 0077. Beim Verbinden fragt „Übernehmen“ einmal, was von diesem Gerät nach Kennel soll und welche Workspaces aus Kennel auf das Gerät kommen, mit einem Vorschlag je Zeile; ohne Bestätigung ändert sich nichts. Ein neuer Workspace fragt zuerst „Wo soll er liegen?“; wo ein bestehender liegt, ändert man in seinem Abschnitt „Ort“: in Kennel ablegen, anderen Speicher wählen, nur noch hier. Jeder Workspace zeigt ein Symbol oder ein eigenes Bild, und ihre Reihenfolge legt man selbst fest. Ist ein Workspace verbunden, sieht er auf allen Geräten gleich aus und steht dort an derselben Stelle (ADR 0043). Überflüssige Workspaces lassen sich nach einer Warnung in Kennel löschen; die Geräte behalten ihre Notizen (ADR 0045). Alles zu Kennel selbst (Verbindung, Speicher, Geräte, Konto) steht auf einer Seite „Kennel“ in den Einstellungen, am Mac als Reiter in ⌘,.

## Suche

Die Suche steht von Anfang an in der Bibliothek, nicht hinter einem späteren Menü.

Sie durchsucht Titel, Text und die Abschrift der Handschrift. Sie besteht nicht auf dem exakten Wortlaut: Großschreibung, Umlaute, `ß`/`ss`, Wortreihenfolge und kleine Abweichungen (ein Buchstabe daneben, wie sie die Erkennung produziert) treffen trotzdem. Ein Schlagwort trifft auch ohne `#`.

Sie versteht keine Synonyme. „Auto“ findet nicht „Wagen“. Dafür wäre ein Modell nötig, und das ist ein anderes Produkt.

## Schlagwörter in der Handschrift

Nach dem Schreiben liest das Gerät die Seite mit der Apple-Texterkennung, auf dem Gerät, ohne Sprachkorrektur, damit seltene Wörter nicht weggebügelt werden. Die Abschrift und die Schlagwörter liegen als Text an der Notiz und wandern mit ihr auf den Server, falls es einen gibt. Der Server sieht die Striche nicht.

Ein einzelnes erkanntes `#` neben einem Wort zählt als Schlagwort, auch wenn es nicht am Wort klebt. Steht das Zeichen zu weit weg, bleibt es keins.

## Lokal zuerst

Die App funktioniert ohne Server vollständig: schreiben, zeichnen, erkennen, suchen. Es gibt eine Bibliothek pro Gerät, ohne Anmeldung. Ein Server ist ein Plus, keine Voraussetzung. Meldet man sich an, wandern alle Notizen des Geräts in den Account. Meldet man sich ab, bleiben sie auf dem Gerät und der Abgleich hört auf. Siehe ADR 0017.

## Sicherung und Export

Auf iPad und iPhone liegen die Notizen im iCloud-Backup des Geräts, wenn es eingeschaltet ist, auf dem Mac in Time Machine. Das ist ein Backup, kein Abgleich. Dazu lässt sich jeder Workspace als ZIP-Datei exportieren: alle Notizen als Markdown und PDF, und eine Kopie, die der Import wieder in die App holt. Eine einzelne Notiz teilt oder exportiert man über ihr Kontextmenü, Text als Markdown, Handschrift als PDF. Siehe ADR 0051.

## Server

Es gibt keine eigene Cloud. Der Server ist Kennel, der selbst betriebene Server des Haushalts für alle eigenen Apps, mit dem Modul `inkhash` (ADR 0067). Der Server speichert Notizen, liefert sie aus und gleicht Geräte ab. Wer ihn erreicht, braucht einen Account: Name und Passwort, ohne E-Mail. Beim ersten Start schreibt der Server einen einmaligen Setup-Token in sein Log. Damit legt man auf der Seite `/admin` im Browser den Admin an, danach gilt der Token nicht mehr. Weitere Accounts legt nur der Admin dort an, mit Name und Startpasswort. Die App meldet sich nur an. Jeder Account hat seine eigenen Notizen.

Workspaces liegen in Kennel unverschlüsselt, als lesbares JSON im gewählten Speicher, z. B. auf der NAS (ADR 0075, 0077). Wer sie sieht, legt der Speicher fest: „Nur ich“ oder „Haushalt“. inkhash bietet keinen Tresor mehr an (teamCato ADR 0009). Workspaces, die noch verschlüsselt sind, wandelt die App von selbst in unverschlüsselte auf demselben Speicher um, sobald ein Gerät ihren letzten Stand lesen kann; andere Geräte folgen, ohne dass etwas verloren geht. Ist kein Gerät mit offenem Tresor mehr da, öffnet man ihn dafür einmal mit dem Wiederherstellungsschlüssel. Siehe ADR 0052 und 0077.

Mit Kennel gleicht jeder Workspace eines Geräts mit genau einem Workspace eines Accounts ab. iCloud und jedes zweite Sync-Ziel sind ausgeschlossen. Sicherung heißt mit Kennel: Kennel sichern, wie es dort beschrieben ist. Ohne Kennel sichern das Geräte-Backup und der Export.

## Name

Ink ist die Handschrift, hash das `#`. Beide Silben wiegen gleich. Als Bildmarke dient ein gezeichnetes `#` aus vier Pinselstrichen: zwei nach rechts ansteigende waagrechte und der rechte senkrechte dunkel, der linke senkrechte heller und dahinter. Kein zusätzlicher Schrägstrich. Das App-Icon ist dieses `#` gemalt, mit Pinselstruktur auf Papier, als Bild in `tools/AppIconArtwork.png`; `make icon` legt es aus: auf iOS als volles Quadrat, das das System rundet, auf dem Mac als eigene abgerundete Platte mit Rand und Schatten, weil macOS Icons nicht maskiert. Farben und Icon teilt inkhash mit den anderen Apps der Familie (ADR 0066). Daneben steht das Wort `inkhash` in einer schlanken Grotesk, `ink` in Deep Blue und `hash` in Grau, nicht in der Schreibschrift der Notiz. Das Logo steht klein unten in der Seitenleiste, kein Knopf. Der Abgleich liegt hinter einem Zahnrad daneben (ADR 0056).

Frühere Namen bleiben verworfen: yana, nono, Kladde, Griffel, shino, shnote, Penmark, inkslash. Nicht umbenennen. nibhash und inkstar sind nur Notizen, keine Alternative.
