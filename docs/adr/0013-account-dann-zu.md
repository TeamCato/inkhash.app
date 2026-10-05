# 0013 Account, dann zu

Status: angenommen. Setup-Token aus der Umgebung und Einladungen ersetzt durch 0021

## Entscheidung

Der Server verlangt eine Sitzung. Der erste Account entsteht mit Name, Passwort und dem Setup-Token `INKHASH_TOKEN`. Danach ist die Registrierung geschlossen. Weitere Accounts brauchen eine Einladung, die einmal gilt und nach 48 Stunden verfällt. Keine E-Mail. Jeder Account hat ein eigenes Notizverzeichnis. Passwörter sind PBKDF2, Sitzungen Zufallswerte, gespeichert als SHA-256.

## Warum

Ein selbst betriebener Server kann im Internet stehen. Ein gemeinsamer Bearer-Token in der App ist dann ein Dauerpasswort ohne Tür. Die Tür soll trotzdem nicht dauerhaft offen sein: wer die Adresse kennt, soll sich nicht selbst eintragen können.

## Nicht

Keine E-Mail, kein zweiter Faktor, keine geteilten Notizbücher zwischen Accounts. Der Setup-Token ist kein Login und wird nicht in die Keychain gelegt.
