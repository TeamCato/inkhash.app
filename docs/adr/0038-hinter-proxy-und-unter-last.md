# 0038 Hinter einem Proxy und unter Last

Status: angenommen

Ergänzt 0016. Ersetzt dort im Abschnitt „Nicht“ den Satz zu `X-Forwarded-For`.

## Entscheidung

Der Server spricht selbst kein TLS. Wer ihn außerhalb des eigenen Netzes erreichen will, stellt einen Reverse-Proxy davor oder benutzt ein VPN, siehe ADR 0040.

**Vertraute Proxys.** `INKHASH_TRUSTED_PROXIES` ist eine Liste aus Adressen und Netzen (`127.0.0.1`, `172.31.87.0/24`, `::1`), durch Komma getrennt. Kommt eine Anfrage von einer dieser Adressen, liest der Server `X-Forwarded-For` von rechts und nimmt die erste Adresse, die kein vertrauter Proxy ist. Ist die Variable leer, gilt wie bisher nur die Adresse der Verbindung. Schickt ein nicht vertrauter Absender `X-Forwarded-For`, schreibt der Server das einmal ins Log, weil sich dann alle Clients hinter diesem Proxy einen Zähler teilen.

**IPv6.** Fehlversuche zählen bei IPv6 pro /64-Netz, nicht pro Adresse. Ein Anschluss bekommt meist ein ganzes /64 und könnte sonst für jeden Versuch eine neue Adresse nehmen. IPv4 und IPv4-in-IPv6 zählen pro Adresse.

**Hashen ist begrenzt.** Höchstens 16 Passwortprüfungen laufen gleichzeitig, davon höchstens 2 für dieselbe Client-Adresse. Darüber antwortet `POST /v1/session` sofort 429 `slow-down`, ohne zu hashen. Vorher prüfte der Server die Sperre vor dem Hashen und zählte den Fehlversuch erst danach; ein Schwall gleichzeitiger Anfragen lief vollständig durch PBKDF2.

**Offene Routen sind klein.** `POST /v1/setup` und `POST /v1/session` nehmen höchstens 16 KiB. Jeder JSON-Body muss als `Content-Type: application/json` kommen, sonst 415 `unsupported-media-type`. Damit kann eine fremde Webseite im Browser keine Anmeldung ohne CORS-Preflight auslösen.

**Dateien gehören dem Server.** Verzeichnisse entstehen mit `0700`, Dateien mit `0600`. Ältere Dateien bekommen die Rechte, wenn sie das nächste Mal geschrieben werden.

**Fehlversuche stehen im Log.** Antwortet `POST /v1/setup` oder `POST /v1/session` mit 401 oder 429, schreibt der Server `auth failed <pfad> <status> from <adresse>`. Name, Passwort und Token stehen nicht darin (P-017). fail2ban kann diese Zeile lesen.

## Warum

TLS gehört an eine Stelle, die Zertifikate erneuern kann; der Server soll ein Prozess ohne Abhängigkeiten bleiben. Hinter einem Proxy sah der Server aber nur dessen Adresse, und 30 Fehlversuche von irgendwem sperrten alle Anmeldungen. Ohne Obergrenze konnte eine einzige Adresse den Thread-Pool mit PBKDF2 für Minuten füllen. Lesbare Hashes und Sitzungen auf einem Mehrbenutzer-System sind ein unnötiges Risiko.

## Nicht

Kein `Forwarded`-Header (RFC 7239), kein `X-Real-IP`. Keine Prüfung des `Host`-Headers. Keine Sperre, die einen Neustart überlebt. Kein Kontingent pro Account: der Admin legt jeden Account selbst an.
