# 0071 Mit Kennel verbinden per Link und Code

Status: angenommen. Das Fenster „Server verbinden“ ersetzt ADR 0077 durch „Mit Kennel verbinden“ (`KennelConnectFlow`).

Setzt teamCato ADR 0004 und Kennel ADR 0018 in inkhash um. Ergänzt 0021 (Accounts legt der Admin an) und 0067 (Abgleich über Kennel). Die Kopplung des Tresors (0054) bleibt ein eigener QR-Code.

## Entscheidung

1. **Ein Feld nimmt alles:** Das Verbinden-Fenster (`ServerConnectView`) hat ein Feld „Adresse oder Link“. Es nimmt eine Adresse, einen Beitrittslink `<server>/join#<code>` oder einen App-Link `inkhash://kennel/join?server=<server>&code=<code>`. Ein Link teilt sich beim Einfügen in Adresse und Code (`JoinLink.parse`). Eine Adresse bleibt, wie sie getippt ist, damit ein bekannter Server wieder gefunden wird.
2. **Code:** Darunter ein Feld für den Beitrittscode. Er wird großzügig gelesen wie in Kennel (`JoinCode.normalized`): Groß/klein egal, `-` und Leerzeichen fallen weg, `O` gilt als `0`, `I` und `L` als `1`; gültig sind zwölf Zeichen aus `0123456789ABCDEFGHJKMNPQRSTVWXYZ`.
3. **Einlösen:** Mit Code sendet die App zuerst nur `{ "code" }` an `POST /v1/join`. Ein Code für „Gerät hinzufügen“ meldet damit an. Antwortet Kennel 400 mit `reason` `name` oder `password`, ist der Code eine Einladung: Die App fragt Name und Passwort (mindestens 8 Zeichen) und sendet beides mit dem Code noch einmal. Die Sitzung landet wie beim Anmelden in der Keychain. Ohne Code bleibt die Anmeldung mit Name und Passwort (`POST /v1/session`).
4. **Fehler:** 401 heißt für jeden Code „gilt nicht mehr oder stimmt nicht“; 409 `name-taken` lässt die Einladung gültig und fragt einen anderen Namen; 429 wie beim Anmelden.
5. **URL-Schema:** Die App meldet `inkhash` auf iPad, iPhone und Mac an (`CFBundleURLTypes`). Ein App-Link öffnet die Einstellungen mit dem Verbinden-Fenster, Adresse und Code vorbelegt. Andere Pfade des Schemas tun nichts.
6. **QR-Code:** Wo eine Kamera ist, scannt das Verbinden-Fenster den QR-Code der Verwaltung mit demselben Scanner wie die Kopplung (`QRScanner`). Es nimmt nur Beitrittslinks mit Code an; der QR-Code der Kopplung wird dort übergangen und umgekehrt.

## Warum

Adressen im Heimnetz abzutippen ist fehleranfällig, und Startpasswörter weiterzugeben unsicher. Ein Format für alle Apps der Familie heißt: ein QR-Code in Kennels Verwaltung, und jede App versteht ihn. Erst nur den Code zu senden, spart eine Frage: Die App weiß vorher nicht, welche Art Code sie hat, und ein Code für ein weiteres Gerät braucht kein Passwort.

## Nicht

- Kein Passwort in einem Link oder QR-Code.
- Kein Finden im Netz per Bonjour, kein Festpinnen von Zertifikaten.
- Die App erzeugt keine Beitrittscodes; das tut Kennels Verwaltung.
- Ohne Kennel bleibt die App voll nutzbar (teamCato ADR 0002).
