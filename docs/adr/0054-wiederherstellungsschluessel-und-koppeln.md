# 0054 Wiederherstellungsschlüssel und Koppeln per QR-Code

Status: angenommen. Ersetzt in ADR 0052 die Passphrase. Die Oberfläche des Tresors (Anlegen, Koppeln, neuer Schlüssel, Zurücksetzen) ersetzt ADR 0077: inkhash bietet keinen Tresor mehr an und wandelt verschlüsselte Workspaces um.

## Entscheidung

Den Tresor (ADR 0052) öffnet keine selbst gewählte Passphrase mehr, sondern ein **Wiederherstellungsschlüssel**, den die App erzeugt. Ein weiteres Gerät bekommt den Account-Schlüssel im Normalfall per **QR-Code** von einem Gerät, auf dem der Tresor offen ist. Den Wiederherstellungsschlüssel braucht man nur, wenn kein solches Gerät zur Hand ist.

### Wiederherstellungsschlüssel

- 24 zufällige Zeichen aus dem Base32-Alphabet von Crockford (`0-9`, `A-Z` ohne `I`, `L`, `O`, `U`), also 120 Bit, dazu ein Prüfzeichen: die ersten 5 Bit von SHA-256 über die 24 Zeichen. Gezeigt in fünf Gruppen zu fünf: `K7QF2-M9XA4-…`.
- Beim Eingeben zählen Groß- und Kleinschreibung, Leerzeichen und Bindestriche nicht. `O` gilt als `0`, `I` und `L` als `1`. Das Prüfzeichen fängt Tippfehler ab, bevor die langsame Ableitung läuft.
- Der Schlüssel verpackt den Account-Schlüssel genau wie vorher die Passphrase: PBKDF2 über die 25 Zeichen in kanonischer Form, gleicher `VaultRecord`, gleicher Server-Vertrag. Die Runden bleiben, auch wenn ein zufälliger Schlüssel sie nicht bräuchte, damit Format und Prüfung des Servers gleich bleiben.
- Die App zeigt den Schlüssel beim Anlegen genau einmal, mit „Kopieren“ und „Sichern…“ (Teilen-Menü, z. B. in die Passwörter-App oder als Ausdruck). Angelegt wird der Tresor erst, wenn man bestätigt, den Schlüssel gesichert zu haben. Kopieren legt ihn auf iOS nur lokal und für zwei Minuten in die Zwischenablage.
- „Neuen Wiederherstellungsschlüssel erzeugen“ ersetzt „Passphrase ändern“: gleicher Account-Schlüssel, neue Verpackung. Der alte Wiederherstellungsschlüssel gilt danach nicht mehr. Geräte mit offenem Tresor merken nichts.
- Zurücksetzen (ADR 0052) verlangt weiter das Login-Passwort und zeigt danach einen neuen Wiederherstellungsschlüssel.

### Koppeln per QR-Code

1. Auf einem Gerät mit offenem Tresor: „Gerät hinzufügen“. Es erzeugt eine Kopplungs-ID (UUID) und ein Einmal-Geheimnis von 32 Byte.
2. Es verschlüsselt den Account-Schlüssel (`VaultKey` als JSON) mit AES-256-GCM. Der Schlüssel dafür kommt per HKDF-SHA256 aus dem Geheimnis (`info` `inkhash-pairing-v1`), zusätzliche Daten sind `inkhash-pairing-v1:<id>`. Das Ergebnis legt es mit `PUT /v1/vault/pairings/<id>` auf den Server.
3. Es zeigt den QR-Code `inkhash-pair:1:<id>:<Geheimnis als Base64url>`. Er nennt weder Server noch Account.
4. Das neue Gerät ist am selben Account angemeldet und wartet auf den Tresor. Es scannt, holt mit `GET /v1/vault/pairings/<id>` das Paket, entschlüsselt es und prüft, dass `keyId` zum Tresor des Servers passt.

Der Server hält höchstens eine offene Kopplung pro Account, im Speicher, fünf Minuten lang. Eine neue ersetzt die alte. `GET` liefert sie einmal und löscht sie. Schließt man den QR-Code vorher, löscht das zeigende Gerät sie mit `DELETE`. Ein Neustart des Servers verwirft offene Kopplungen.

Scannen geht auf iPad, iPhone und auf Macs mit Kamera, über AVFoundation und Vision. Ohne Kamera fehlt der Knopf, dann hilft der Wiederherstellungsschlüssel. Jedes Gerät mit offenem Tresor kann den QR-Code zeigen, auch ein Mac.

## Warum

Eine selbst gewählte Passphrase war die Hürde: Man muss sich etwas Langes ausdenken, es merken und auf jedem Gerät eintippen. Ein erzeugter Schlüssel ist stärker als fast jede Passphrase und muss nicht im Kopf bleiben. Er gehört an einen sicheren Ort, nicht ins Gedächtnis.

Koppeln deckt den häufigen Fall ab: Ein Gerät ist eingerichtet, ein zweites kommt dazu. Das Geheimnis im QR-Code ist zufällig und 256 Bit lang. Der Server, der das Paket kurz hält, kann es also nicht durch Raten öffnen, die Ende-zu-Ende-Verschlüsselung bleibt. Der Code allein nützt nichts ohne Anmeldung am Account. Nach fünf Minuten oder nach dem ersten Abruf ist er wertlos, ein abfotografierter Code also auch. Den Schlüssel direkt in den Code zu legen, wäre einfacher gewesen, hätte aber aus jedem Foto des Bildschirms einen dauerhaften Schlüssel gemacht.

Ein kurzer Code zum Abtippen statt des QR-Codes scheidet aus: Was sich bequem tippen lässt, kann der Server in Sekunden durchprobieren.

## Nicht

- Kein iCloud-Schlüsselbund und kein anderer Abgleich des Schlüssels über Apple (Grenze in `AGENTS.md`).
- Keine Passphrase mehr, auch nicht wahlweise. Es gibt noch keine Nutzer mit Passphrase-Tresor. Wer einen aus der Entwicklung hat, setzt ihn zurück.
- Keine Kopplung ohne Server, etwa über Bluetooth oder das lokale Netz.
- Kein Gerät, das andere Geräte sieht oder abmeldet. Wer den Account-Schlüssel hat, behält ihn, bis man den Tresor zurücksetzt.
