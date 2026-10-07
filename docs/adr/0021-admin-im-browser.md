# 0021 Accounts entstehen im Browser, beim Admin

Status: angenommen

Ersetzt in 0013 den Setup-Token aus der Umgebung und die Einladungen. Ersetzt in 0016 die Mindestlänge des Setup-Tokens. Ersetzt in 0018 die Registrierung im Server-Dialog.

## Entscheidung

Solange es keinen Account gibt, erzeugt der Server bei jedem Start einen zufälligen Setup-Token (24 Bytes, base64url) und schreibt ihn einmal in sein Log, zusammen mit dem Pfad `/admin`. Der Token liegt nur im Speicher. Ein Neustart vor der Einrichtung erzeugt einen neuen. `INKHASH_TOKEN` gibt es nicht mehr.

Unter `/admin` liefert der Server eine einzelne statische Seite aus. Mit dem Setup-Token legt man dort den ersten Account an. Er ist Admin. Danach ist der Setup-Token ungültig, und der Server erzeugt beim nächsten Start keinen mehr.

Der Admin ist ein gewöhnlicher Account mit eigenen Notizen und meldet sich in der App wie jeder andere an. Zusätzlich darf er auf `/admin` weitere Accounts anlegen: Name und Startpasswort, die er selbst weitergibt. Mehr kann die Seite nicht. Es gibt genau einen Admin.

Die App legt keine Accounts mehr an und kennt weder Setup-Token noch Einladungen. Sie meldet sich nur an. Ist der Server noch nicht eingerichtet, verweist sie auf `/admin`.

Server mit Accounts von vorher: Beim Start wird der älteste Account Admin, wenn keiner Admin ist. Offene Einladungen gelten nicht mehr. Das Verzeichnis `invites/` bleibt liegen und wird nicht mehr gelesen.

Die Seite hält die Sitzung im `sessionStorage` und schickt sie als Bearer, wie die App. Keine Cookies, also kein CSRF. Sie setzt Text nur über `textContent`, und eine strenge Content-Security-Policy lässt nur das eigene Skript zu.

## Warum

Ein Token, den man selbst erfinden, in eine Umgebungsvariable legen und dann in die App tippen muss, ist der umständlichste Teil der Einrichtung. Einladungen brauchten zwei Geräte und einen Code, der in 48 Stunden verfällt. Ein Admin, der Accounts direkt anlegt, ist für einen selbst betriebenen Server mit wenigen Personen einfacher. Ein zufälliger Token aus dem Server selbst kann nicht zu kurz oder `dev` sein.

Die Seite im Browser statt in der App, weil Verwaltung selten ist und die App dafür keine eigenen Bildschirme bekommen soll.

## Nicht

Kein Passwort ändern, kein Account löschen, kein zweiter Admin, keine Rechte darüber hinaus (geändert durch 0046). Wer das Admin-Passwort vergisst, braucht Zugriff auf das Datenverzeichnis. Die Seite rendert keine Notizen; der Server bleibt bei Speichern, Ausliefern und Abgleichen.
