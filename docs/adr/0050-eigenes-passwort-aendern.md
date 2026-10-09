# 0050 Eigenes Passwort ändern

Status: angenommen

## Entscheidung

Ein Account ändert sein Passwort selbst, in der App unter Server → „Passwort ändern“. Dafür gibt es `PUT /v1/password` mit `{ "current", "password" }`. Der Server prüft das bisherige Passwort wie beim Anmelden: dieselbe Sperre pro Name und pro Adresse, dieselbe Grenze für gleichzeitige Prüfungen, dieselbe Zeile im Log für fail2ban.

Ein falsches bisheriges Passwort ist 403 `wrong-password`, nicht 401. Die Sitzung gilt weiter, und die App darf sie deshalb nicht verwerfen.

Danach enden alle anderen Sitzungen des Accounts, die fragende bleibt. Das ist dieselbe Regel wie beim Setzen durch den Admin (ADR 0046).

## Warum

Der Admin vergibt Startpasswörter und kennt sie damit. Ohne eigenen Wechsel bliebe das so. Das bisherige Passwort zu verlangen, schützt vor einem liegengelassenen, entsperrten Gerät.

## Nicht

Kein Zurücksetzen per E-Mail, es gibt keine E-Mail. Wer sein Passwort vergessen hat, bekommt vom Admin ein neues. Das Login-Passwort ist nicht die Passphrase des Tresors (ADR 0052).
