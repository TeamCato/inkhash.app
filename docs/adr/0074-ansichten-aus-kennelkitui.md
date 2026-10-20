# 0074 Ansichten aus KennelKitUI

Status: angenommen

Ergänzt 0073. Setzt teamCato ADR 0006 Punkt 2 und Kennel ADR 0023 Punkt 3 um.

## Entscheidung

1. inkhash zeigt die Kennel-Fenster aus `KennelKitUI` (Produkt im Paket `kennel` ab 0.6.0, in `project.yml` eingebunden): „Server verbinden“ (`KennelConnectSection`: im Netz gefunden, Adresse oder Link mit Prüfung auf das Modul `inkhash`, QR-Code, Code, Name und Passwort, Einladung), „Weiteres Gerät verbinden …“ (`KennelDeviceCodeView`), „Passwort ändern“ (`KennelPasswordChangeView`), den QR-Scanner (`KennelQRScanSheet`, auch für die Kopplung des Tresors, ADR 0054) und QR-Codes (`KennelQRCodeView`).
2. Name und Farbe gibt inkhash über `KennelAppBrand.inkhash` (`Ink.accent`).
3. Die App behält, was nur sie weiß: Sitzungen je Server, Status-Zeile, die Seite des Servers nach dem Anmelden. Die Ansichten rufen dafür `ServerSessions` und `AppModel` über Closures.
4. Weg sind `QRCodes.swift`, `KennelFinder`, das Prüfen der Adresse in `ServerSessions` und `PasswordChange` im Kern; ihre Tests liegen in KennelKitUI.

## Warum

Xoot zeigt dieselben Fenster; so sieht Verbinden in beiden Apps gleich aus und wird an einer Stelle verbessert.

## Nicht

- Das Formular zeigt Code und Name gleich, nicht erst nach geprüfter Adresse wie vorher; ist Kennel noch nicht eingerichtet, steht dort der Weg zur Verwaltung.
