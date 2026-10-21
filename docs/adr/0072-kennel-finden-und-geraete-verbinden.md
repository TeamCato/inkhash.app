# 0072 Kennel finden und weitere Geräte verbinden

Status: angenommen. „Weiteres Gerät verbinden …“ steht seit ADR 0077 auf der Seite „Kennel“.

Setzt teamCato ADR 0005 und Kennel ADR 0019 in inkhash um. Ergänzt 0071 (Verbinden per Link und Code).

## Entscheidung

1. **Finden:** Solange das Verbinden-Fenster offen ist, sucht die App per Bonjour nach `_kennel._tcp` (Network-Framework, `NWBrowser`). Gefundene Kennel stehen unter „Im Netz gefunden“ mit ihrem Instanznamen. Ein Tipp löst den Dienst auf, indem die App ihn über IPv4 anspricht (Kennel kündigt nur IPv4 an), und trägt `http://<ip>:<port>` ins Adressfeld ein. Die Adresse wird dann wie getippt geprüft. Angemeldet wird erst mit Code oder Name und Passwort; die Adresse von Hand bleibt immer möglich.
2. Das Suchen liegt hinter dem Protokoll `KennelBrowsing`; die Umsetzung `BonjourKennelBrowser` und die Adresse aus Host und Port (`KennelDiscovery.address`, IPv4 aus den Bytes, ohne Schnittstelle) gehören dem Kern und sind dort getestet. `KennelFinder` in der App zeigt die Funde.
3. `Info.plist` auf iPad, iPhone und Mac nennt `NSBonjourServices` = `_kennel._tcp` und `NSLocalNetworkUsageDescription`. Der Mac hat schon `com.apple.security.network.client`.
4. **Weiteres Gerät verbinden:** In den Einstellungen eines angemeldeten Servers erzeugt „Weiteres Gerät verbinden …“ einen Code `device` (`POST /v1/join-codes`). Die App zeigt ihn als Text, als Beitrittslink `<server>/join#<code>` und als QR-Code dieses Links (Core Image, `QRCodeView`), mit Ablaufzeit. „Zurückziehen“ löscht ihn (`DELETE /v1/join-codes/{id}`); ist er schon eingelöst oder abgelaufen, gilt das auch als zurückgezogen.
5. Einladungen erzeugt die App nicht; das bleibt in Kennels Verwaltung bei den Admins.

## Warum

Mit Bonjour muss niemand die Adresse kennen. Wer schon ein Gerät verbunden hat, holt das nächste dazu, ohne die Verwaltung im Browser zu öffnen. Über IPv4 statt über den `.local`-Namen aufzulösen, braucht keinen zweiten Namensdienst und entspricht dem, was Kennel ankündigt.

## Nicht

- Kein automatisches Verbinden mit dem ersten gefundenen Kennel.
- Kein Suchen im Hintergrund, nur solange das Verbinden-Fenster offen ist.
- Kein IPv6 und kein `path` aus dem TXT-Eintrag in diesem Schritt; Kennel liegt an der Wurzel.
