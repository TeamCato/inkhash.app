# 0052 Ende-zu-Ende-Verschlüsselung

Status: angenommen

## Entscheidung

Notizen und Blobs gehen nur noch verschlüsselt auf den Server. Der Server speichert Bytes, die er nicht lesen kann. Das ist Pflicht: Eine App mit diesem Stand gleicht nur mit einem Account ab, der einen Tresor hat.

### Tresor

Jeder Account hat höchstens einen Tresor (`/v1/vault`). Er hält den Schlüssel des Accounts, verschlüsselt mit einer **Passphrase**, die nur die Geräte kennen:

- Der Schlüssel sind 32 Zufallsbytes, erzeugt auf dem Gerät, das den Tresor anlegt. `keyId` ist eine UUID dazu.
- Aus der Passphrase (Unicode-NFC, mindestens 12 Zeichen) macht PBKDF2-HMAC-SHA256 mit 600.000 Runden und 16 Byte Salz einen Schlüssel. Damit ist der Account-Schlüssel per AES-256-GCM verpackt (`wrapped`), mit `inkhash-vault-v1:<keyId>` als zusätzlichen Daten.
- Der Server hält `{ keyId, kdf: { name, rounds, salt }, wrapped, epoch }`. Ohne Passphrase nützt ihm das nichts.
- Das Gerät legt den entpackten Schlüssel in den Schlüsselbund, pro Server. Die Passphrase selbst speichert es nicht.

Die Passphrase ist nicht das Login-Passwort. Das Login-Passwort kennt der Server bei jeder Anmeldung und der Admin beim Anlegen (ADR 0046, 0050). Die Passphrase sieht keiner von beiden.

### Was verschlüsselt ist

Aus dem Account-Schlüssel leitet HKDF-SHA256 drei Schlüssel ab: für Inhalte, für Nonces und für Blob-Namen.

- **Notiz:** Der ganze Inhalt, also Art, Titel, Text, Abschrift, Schlagwörter, Seiten, Elemente, Pfad, Favorit, Papier und Erstellungsdatum, wird als JSON mit zlib gepackt und mit AES-256-GCM verschlüsselt. Die Nonce ist ein HMAC über Klartext und Notiz-ID (synthetische Nonce). Gleicher Inhalt ergibt so gleiche Bytes, und der Retry-Vergleich des Servers funktioniert weiter. Verschiedener Inhalt ergibt verschiedene Nonces. Die Notiz-ID ist zusätzliche Daten, der Server kann also keine Inhalte zwischen Notizen vertauschen.
- **Blob:** Zeichnungen, Fotos und Workspace-Bilder auf dieselbe Weise, mit dem Klartext-Hash als zusätzlichen Daten. Der Name auf dem Server ist ein HMAC über den Klartext-Hash. Lokal behalten Blobs ihren Klartext-Hash. Das Gerät prüft nach dem Entschlüsseln, dass der Hash stimmt.

Im Klartext bleiben: Account-Name, Namen und Symbole der Workspaces, ihre Reihenfolge, Notiz-IDs, Revisionen, Zeitstempel des Servers, ob eine Notiz im Papierkorb liegt, und die Größen. Der Abgleich braucht das. Mehr verbirgt dieser Schritt nicht.

### Auf dem Draht

Eine verschlüsselte Notiz hat `schemaVersion: 2` und statt der Inhaltsfelder `sealed`, Base64. Ein `PUT` darf `deleted: true` mitschicken, dann bleibt oder wird sie Grabstein. So wandern auch Notizen im Papierkorb verschlüsselt, ohne kurz wiederhergestellt zu werden. Hat ein Account einen Tresor, lehnt der Server Notizen mit `schemaVersion: 1` ab (400 `reason: "sealed"`), ebenso Blobs, deren Name ihr eigener SHA-256 ist, also Klartext. Ohne Tresor lehnt er verschlüsselte Notizen ab (400 `reason: "no vault"`).

### Umstieg

Beim ersten Start mit diesem Stand fragt die App je angemeldetem Server nach dem Tresor:

- **Kein Tresor auf dem Server:** Die App bittet, eine Passphrase festzulegen, und legt ihn an.
- **Tresor da, Schlüssel nicht auf dem Gerät:** Die App fragt nach der Passphrase.
- **Server ohne Tresor-Unterstützung:** Der Abgleich ruht, bis der Server aktualisiert ist.

Bis dahin gleicht die App mit diesem Server nicht ab. Lokal geht alles weiter (ADR 0017).

Danach liest jede Bibliothek einmal alle Notizen vom Server (Cursor 0). Was noch im Klartext liegt, geht verschlüsselt neu hoch, gelöschte Notizen als Grabstein. Erst wenn eine Bibliothek damit fertig ist, merkt sie sich den Schlüssel (`sealed.txt`). Ein Abbruch fängt beim nächsten Abgleich von vorn an. Liegt in einem Workspace keine Klartext-Notiz mehr, löscht der Server dort alle Klartext-Blobs außer dem aktuellen Workspace-Bild, einmal. Das Bild ersetzt das nächste Gerät, das das Aussehen abgleicht.

### Passphrase ändern, vergessen

- **Ändern:** Der Schlüssel bleibt, nur `wrapped` und `kdf` werden neu. Geräte mit dem Schlüssel im Schlüsselbund merken nichts.
- **Vergessen:** „Tresor zurücksetzen“ verlangt das Login-Passwort. Der Server verschiebt alle Notizen und Blobs des Accounts nach `deleted/vault-reset-<zeit>/`, löscht den Tresor und zählt `epoch` hoch. Das Gerät legt einen neuen Tresor an und lädt seine Notizen neu hoch. Andere Geräte fragen nach der neuen Passphrase und binden ihre Bibliothek neu (ADR 0017, `Library.bind`). Was nur auf dem Server lag, ist dann weg. Die App sagt das vorher.

## Warum

Der Server läuft auf fremder oder geteilter Hardware, ein Backup des Datenverzeichnisses landet sonstwo. Bisher stand dort jede Notiz lesbar. Weil der Server nie in Notizen schauen musste (ADR 0009, 0010: keine Suche, keine Tags auf dem Server), kostet die Verschlüsselung keine Funktion.

PBKDF2 statt scrypt oder Argon2, weil CommonCrypto es auf allen Apple-Plattformen ohne Abhängigkeit hat. Die Rundenzahl steht im Tresor und kann später steigen. Die synthetische Nonce statt einer zufälligen hält den Retry nach einer verlorenen Antwort ohne Konflikt (API.md). Sie verrät nur, dass zwei Fassungen gleich sind, und das verrät die Revision ohnehin.

Pflicht statt Schalter, weil ein Account mit beiden Formaten zwei Wege im Code und einen leicht übersehenen unverschlüsselten Rest hieße.

## Nicht

- Kein Teilen zwischen Accounts, keine Schlüssel pro Workspace.
- Keine Verschlüsselung von Workspace-Namen und -Symbolen. Sie stehen in der Liste vor dem Entsperren.
- Keine Wiederherstellung ohne Passphrase. Wer sie verliert, behält die Notizen auf seinen Geräten, nicht auf dem Server.
- Der Server verschlüsselt nichts selbst und prüft nicht, ob ein Gerät die richtige Passphrase kennt.
- Was schon in `deleted/`, `deleted-accounts/` oder in Backups des Datenverzeichnisses liegt, bleibt im Klartext. Das muss der Betreiber selbst löschen.
