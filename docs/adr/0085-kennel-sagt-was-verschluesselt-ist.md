# 0085 Kennel sagt, was verschlüsselt ist; unverschlüsselt weiterführen auf Wunsch

Status: angenommen. Dominik am 2026-10-27 („a single unlock led to the fact that now all my workspaces are encrypted“,
„on iphone the kennel <-> local relation of a workspace was lost“, „adding it was not obvious“, „kennel mentions xoot in
inkhash“). Ergänzt ADR 0082; ändert dessen Punkt 5 und den Satz des Nachtrags zu Xoot. Kennel ADR 0026 und 0065 bleiben.

## Kontext

Freischalten verschlüsselt nichts. Kennel führt aber jeden inkhash-Workspace aus der Zeit vor der Wahl pro Workspace
(auch `main`) als verschlüsselt (Kennel ADR 0026 Punkt 1). Die Umwandlung in lesbare Workspaces aus ADR 0077 hat
ADR 0082 abgeschaltet. Solche Workspaces lagen deshalb still, bis jemand freischaltete; danach glichen sie verschlüsselt
ab und trugen das Schloss. Für Dominik sah das aus, als hätte ein Freischalten alles verschlüsselt.

Dazu kamen drei Fehler:

- `WorkspaceLink.sealed` wurde beim Verknüpfen geraten (alte Links ohne Feld: verschlüsselt) und nie mit Kennel
  abgeglichen.
- Hatte ein Gerät eine Umwandlung beendet und den alten Workspace in Kennel gelöscht, strich ein anderes Gerät (das
  iPhone) seine Verknüpfung, statt dem Nachfolger zu folgen. Das Folgen war mit ADR 0082 weggefallen.
- Einen Kennel-Workspace holte man nur im Blatt „Neuer Workspace“ ganz unten, nach der Wahl „In Kennel“. Einen
  Workspace, der nur hier liegt, konnte man nicht mit einem vorhandenen Kennel-Workspace verbinden.

## Entscheidung

1. **Kennel sagt, was verschlüsselt ist.** Jeder Abgleich übernimmt `sealed` aus Kennels Liste in die Verknüpfung
   (`DeviceSetup.adoptEncryption`). Weicht sie ab, gleicht der Workspace einmal zusammenführend ab (`Relinker.adopt`),
   statt neu zu beginnen.
2. **„Unverschlüsselt weiterführen …“** im Abschnitt „Ort“ eines verschlüsselten Workspace, mit Rückfrage. Nur wenn
   freigeschaltet: erst ein verschlüsselter Abgleich, dann übernimmt ein lesbarer Workspace mit demselben Namen im
   selben Speicher alle Notizen, danach löscht inkhash den alten in Kennel (Ablauf aus ADR 0077, `Conversion`,
   `WorkspaceConverter.convert`). Es geschieht nur auf Wunsch, nie von selbst. Verschlüsseln bleibt die Wahl beim
   Anlegen eines neuen Workspace (ADR 0082 Punkt 3).
3. **Andere Geräte folgen.** Verschwindet der Kennel-Workspace einer Verknüpfung und gibt es einen lesbaren Nachfolger
   mit demselben Namen, der Notizen mit diesem Workspace teilt (`ConversionPlanner.successor`), verknüpft inkhash ihn
   und führt zusammen (`WorkspaceConverter.follow`). Ohne Nachfolger bleibt der Workspace „Nur hier“ wie bisher
   (ADR 0045).
4. **Hinzufügen sichtbar.** Das Workspace-Menü der Seitenleiste zeigt „Aus Kennel hinzufügen“ mit jedem
   Kennel-Workspace, der noch nicht hier ist; ein Tipp holt ihn. Im Blatt „Neuer Workspace“ steht „Schon in Kennel“
   direkt unter der Wahl „In Kennel“. Ein Workspace, der nur hier liegt, hat im Abschnitt „Ort“ zusätzlich
   „Mit Kennel-Workspace verbinden …“; die Notizen beider kommen zusammen, keine doppelt. Dasselbe Zusammenführen gilt
   für „Übernehmen“ beim Verbinden mit Kennel.
5. **Keine anderen Apps in inkhashs Texten.** Das Freischalten-Blatt auf dem Mac nennt ein anderes Gerät, nicht Xoot.

## Nicht

- Kein Umschalten in Kennel selbst: lesbar wird ein Workspace nur über einen neuen Nachfolger.
- Kein Umwandeln ohne Schlüssel: ohne Freischalten sind die Notizen hier nicht lesbar.
