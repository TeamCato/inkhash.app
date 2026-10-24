# 0077 Kennel-Ablauf nach teamCato ADR 0009, ohne Tresor

Status: angenommen, Punkte 5 (immer unverschlüsselt), 8 und 9 abgelöst durch ADR 0082. Dominik am 2026-10-21 (teamCato ADR 0009, „umwandeln“). Setzt teamCato ADR 0009 und Kennel ADR
0028 in inkhash um. Ersetzt: in ADR 0020 die Wahl von Server und Server-Workspace im Workspace-Editor; die
Oberfläche des Tresors aus ADR 0052 und 0054 (Anlegen, Koppeln, neuer Wiederherstellungsschlüssel, Zurücksetzen,
das Blatt, das sich von selbst öffnet); die Fenster aus ADR 0071, 0072 und 0074 („Server verbinden“, die Seite des
Servers); ADR 0073 Punkt 4 „Mehrere Server bleiben möglich“; den Schalter „Verschlüsselt“ aus ADR 0075 Punkt 1 und
dessen Punkt 4; ADR 0076 Punkt 1 (Umziehen im Editor). Format, Server-Vertrag und Sync aus ADR 0052 bleiben, solange
es verschlüsselte Workspaces gibt.

## Entscheidung

1. **Wörter:** In der Oberfläche heißt es „Kennel“, nie „Server“: „Mit Kennel verbinden“, „Kennel nicht
   erreichbar“, „In Kennel löschen …“, eine behaltene Fassung aus einem Konflikt heißt „Titel (Kennel)“. Orte heißen
   „Nur hier“, „Abgeglichen“, „Zieht um“ (`KennelPlace`); „In Kennel“ gibt es für inkhash nicht, ein Workspace liegt
   immer auch auf dem Gerät.
2. **Ein Kennel:** `setup.json` behält die Liste `servers`, hat aber höchstens einen Eintrag (`WorkspaceRegistry.kennel`).
   Kennt ein Gerät von früher mehrere, bleibt beim ersten Start der angemeldete Server, mit dem die meisten Workspaces
   abgleichen; ist keiner angemeldet, der mit den meisten Workspaces; bei Gleichstand der erste der Liste
   (`DeviceSetup.keepOneKennel`). Die Workspaces der anderen bleiben mit allen Notizen als „Nur hier“, ihre Sitzungen
   und Tresor-Schlüssel verlassen das Gerät. Wer an einer anderen Adresse anmeldet, ersetzt den Kennel auf dieselbe Art.
3. **Eine Seite „Kennel“** aus KennelKitUI (`KennelSettingsPage`, in der App `KennelSettingsView`): am Mac als Reiter
   „Kennel“ in ⌘, neben „Text“, auf iPad und iPhone als erste Zeile der Einstellungen. Verbindung mit Statuszeile und
   „Jetzt abgleichen“, „Speicher für Inkhash“ (Standard und die Speicher, die inkhash nutzen darf, mit der Zahl der
   Workspaces darauf, „Neuer Speicher …“, „Bearbeiten …“), Geräte („Weiteres Gerät verbinden …“), Konto („Passwort
   ändern …“, „Von Kennel trennen …“). Trennen meldet ab, vergisst den Kennel und macht jeden Workspace zu „Nur hier“;
   nichts geht verloren, in Kennel bleibt alles liegen. Die Seite des Servers (`ServerDetailView`) entfällt.
4. **Verbinden** ist `KennelConnectFlow` (Finden › Anmelden › Übernehmen); `inkhash://kennel/join` öffnet es
   vorbelegt, „Bitte neu anmelden“ mit Adresse und Name. „Übernehmen“ (`TakeOverPlanner`) listet:
   - jeden Workspace, der nur hier liegt, mit „Nur hier lassen“, „In Kennel · <Speicher>“ je Speicher und „Mit „X“
     abgleichen“ für einen Kennel-Workspace gleichen Namens oder den, mit dem er früher abglich. Vorschlag: der
     frühere Partner, sonst der Namensvetter, sonst „Privat“ nach „In Kennel · Standard“, alles andere „Nur hier
     lassen“;
   - jeden Kennel-Workspace, der nicht hier ist, mit „Hinzufügen“ (Vorschlag) oder „Nicht jetzt“. Was schon über
     „Mit … abgleichen“ verbunden wird, kommt nicht ein zweites Mal dazu.
   „Später“ lässt alles, wie es ist.
5. **Neuer Workspace** fragt zuerst „Wo soll er liegen?“ (`KennelPlacePicker`): „Auf diesem Gerät“ oder „In Kennel“
   mit Speicher und „Neuer Speicher …“, darunter Name und Aussehen und „Schon in Kennel“ mit den Kennel-Workspaces,
   die hier fehlen. Ohne Verbindung öffnet „In Kennel“ das Verbinden und kehrt zurück. Ein neuer Kennel-Workspace ist
   immer unverschlüsselt (`sealed: false`); es gibt keinen Schalter.
6. **Ort** im Bearbeiten-Blatt eines Workspace (`KennelPlaceSection`): „Nur hier“ bietet „In Kennel ablegen …“
   (Speicher wählen; ein neuer, unverschlüsselter Kennel-Workspace nimmt alle Notizen); „Abgeglichen“ bietet
   „Anderer Speicher …“ (Umzug nach ADR 0076, nur wenn Kennel `workspaceMove` meldet), „Nur noch auf diesem Gerät …“
   (der Abgleich endet, beide Kopien bleiben) und „In Kennel löschen …“ (ADR 0045). Während eines Umzugs steht dort
   „Zieht um“ ohne Aktionen.
7. **Marken und Status:** Workspace-Wahl und Einstellungen zeigen die Marke (`KennelPlaceBadge`), nur solange ein
   Kennel verbunden ist. Der Fuß der Seitenleiste zeigt `KennelStatusFooter`, abgeleitet aus `KennelSyncState`:
   abgelaufene Sitzung „Bitte neu anmelden“ (ersetzt den Hinweis über der Liste), fehlendes Modul „Inkhash ist in
   diesem Kennel aus“ mit dem Weg zur Verwaltung, sonst nicht erreichbar, gleicht ab, abgeglichen oder fehlgeschlagen.
   Was eine einzelne Notiz betrifft (abgelehnt, Konflikt), bleibt in der Zeile darunter.
8. **Kein Tresor mehr in der Oberfläche.** Kein „Tresor anlegen“, kein Koppeln, kein neuer Wiederherstellungsschlüssel,
   kein Zurücksetzen, kein Blatt, das sich von selbst öffnet. Übrig bleibt `ConversionSheet`: was „Umwandeln“ heißt,
   und „Tresor öffnen“ mit dem Wiederherstellungsschlüssel für den Fall, dass kein Gerät mit offenem Tresor mehr da ist.
   Ein Tresor-Schlüssel, der schon im Schlüsselbund liegt, wird weiter benutzt.
9. **Umwandeln** (`ConversionPlanner`, `Conversion`, `Relinker` im Kern, `WorkspaceConverter` in der App), bei jedem
   Abgleich für jeden Workspace, der mit einem verschlüsselten Kennel-Workspace abgleicht:
   1. Ein Gerät wandelt um, wenn es den letzten Stand hat: mit Schlüssel nach einem verschlüsselten Abgleich ohne
      Ablehnung; ohne Schlüssel, wenn Kennel nach dem Cursor der Bibliothek nichts Neues hat (ein leerer Workspace
      braucht so nie einen Schlüssel). Sonst steht der Status auf „Umwandeln“ mit „Tresor öffnen …“. Kann Kennel keine
      unverschlüsselten Workspaces (`plainWorkspaces`) oder zieht der Workspace gerade um, wartet es mit „Umwandeln“
      ohne Aktion.
   2. Es nimmt einen unverschlüsselten Namensvetter auf demselben Speicher, den kein anderer Workspace hier nutzt,
      sonst legt es einen an: gleicher Name, gleicher Speicher, `sealed: false`.
   3. Bevor eine Notiz hochgeht, schreibt es in `setup.json` die neue Verbindung und `Workspace.retiring` (alter
      Kennel-Workspace, bis wohin es ihn gelesen hat, „ich lösche ihn“). Ein Abbruch macht beim nächsten Abgleich
      mit demselben Nachfolger weiter. Aussehen und Platz in der Reihenfolge gehen mit.
   4. `Relinker.adopt` statt `Library.bind`: was Kennel im Nachfolger schon hat und hier unverändert ist, nimmt die
      Bibliothek von Kennel; was hier geändert ist, bleibt und geht auf Kennels Revision hoch; was Kennel nicht hat,
      geht neu hoch. Der Papierkorb bleibt auf dem Gerät und geht nicht mit hinüber. Dann lädt der normale Abgleich
      alles unverschlüsselt hoch, Blobs vor ihren Notizen.
   5. Erst wenn keine Notiz mehr ungesendet und keine abgelehnt ist, schaut es, ob seit seinem Lesen jemand in den
      alten Workspace geschrieben hat. Wenn ja, holt es diese Notizen mit dem Schlüssel (`Relinker.takeLate`; eine hier
      geänderte Notiz behält die Änderung, die späte Fassung wird eine eigene Notiz) und gleicht noch einmal ab; ohne
      Schlüssel wartet es auf ein Gerät mit Schlüssel. Wenn nein, löscht es den alten Workspace in Kennel. Vorher wird
      nie etwas gelöscht.
10. **Andere Geräte folgen:** Fehlt der alte Workspace in Kennels Liste, sucht ein Gerät den Nachfolger unter den
    unverschlüsselten Workspaces gleichen Namens, die hier niemand nutzt, und nimmt den, der die meisten Notizen mit
    der eigenen Bibliothek teilt (Notiz-IDs aus dem Änderungsprotokoll; die Umwandlung behält sie). Hatte der
    Workspace nie eine abgeglichene Notiz, genügt ein einziger Namensvetter. Gefunden: neue Verbindung mit
    `retiring` ohne Löschen, `Relinker.adopt`, dann der normale Abgleich; eigene Änderungen gehen hoch, nichts wird
    zum Konflikt mit sich selbst. Nicht gefunden: der Workspace bleibt „Nur hier“, mit allen Notizen. Kennels
    Workspaces tragen kein Feld für einen Verweis, und Kennels Vertrag bleibt (teamCato ADR 0009, „Nicht“).
11. **Aussehen ohne Tresor:** Bilder unverschlüsselter Workspaces gehen unverschlüsselt hoch, unter ihrem SHA-256.
    `SealedLooks` versiegelt nur noch Bilder verschlüsselter Workspaces und nur mit Schlüssel; ein versiegeltes Bild in
    einem unverschlüsselten Workspace geht mit Schlüssel einmal unverschlüsselt neu hoch. Ein Bild, das das Gerät
    nicht lesen kann, bleibt hier, wie es ist; das Aussehen eines verschlüsselten Workspace schreibt nur ein Gerät
    mit Schlüssel.

## Warum

teamCato ADR 0009 legt einen Ablauf für alle Apps fest, und Punkt 10 nimmt den Tresor aus inkhash. Wer schon
verschlüsselte Workspaces hat, soll nichts tun müssen, außer im schlimmsten Fall einmal den Wiederherstellungsschlüssel
eingeben. Den Nachfolger am Namen und an geteilten Notiz-IDs zu erkennen, braucht keine Änderung an Kennel; geteilte
IDs gibt es nur, wenn wirklich dieselben Notizen drinliegen, und wo der Beweis fehlt, bleibt der Workspace lieber „Nur
hier“, als in einen fremden zu laufen. Ein Gerät ohne Schlüssel, dessen Bibliothek schon alles hat, kann selbst
umwandeln, weil es den Klartext ja hat.

## Nicht

- Keine Änderung an Kennels Server-Vertrag; der Tresor und die Routen bleiben dort (`encryption: "optional"`).
- Kein Löschen des alten Workspace, bevor alles im Nachfolger liegt, und kein Löschen ohne Prüfung auf späte Notizen.
- Kein Hochladen des Papierkorbs in den Nachfolger.
- Wandeln zwei Geräte gleichzeitig um, kann ein leerer zweiter Nachfolger in Kennel liegen bleiben; er nimmt keine
  Notiz mit und lässt sich in „Ort“ oder in Kennel löschen.
- Kein Zurück zur Verschlüsselung in diesem Schritt; das entscheidet eine spätere ADR (teamCato ADR 0009 Punkt 10).
