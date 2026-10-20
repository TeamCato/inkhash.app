# 0073 inkhash nutzt KennelKit

Status: angenommen

Setzt teamCato ADR 0006 und Kennel ADR 0023 in inkhash um. Ersetzt die Umsetzung aus 0071 und 0072, nicht ihre Entscheidungen.

## Entscheidung

1. **Abhängigkeit:** `InkhashCore` bindet das Swift-Paket KennelKit aus dem Repo `kennel` ein: `.package(url: "https://github.com/teamcato/kennel", .upToNextMinor(from: "0.5.0"))`, Produkt `KennelKit`: Solange Kennel 0.x ist, darf ein Minor-Release KennelKit brechen (Kennel ADR 0023). Es ist die erste Abhängigkeit außerhalb der Systemframeworks; KennelKit selbst nutzt nur Systemframeworks. Die Apps nutzen Typen aus KennelKit direkt und binden das Produkt deshalb auch in `project.yml` ein. Zum Entwickeln gegen einen lokalen Stand: `KENNELKIT_DIR=../kennel` (ein Ordner namens `kennel`, relativ zum Repo oder absolut) beim Bauen und Testen setzen; dann nimmt `Package.swift` von `InkhashCore` das Paket aus dem Ordner, und Xcode nimmt diesen lokalen Stand auch für die Apps. Eine eigene Variable, nicht `KENNEL_DIR` des Vertragstests, damit der Test gegen einen lokalen Kennel nicht nebenbei das Paket tauscht.
2. **Aus KennelKit**, nicht mehr aus `InkhashCore`: Adressen lesen und zeigen (`KennelAddress`; `ServerAddress.valid` fällt weg, `ServerAddress.host` zeigt über `KennelAddress.display`), Beitrittscodes und -links (`JoinCode`, `JoinLink.parse(_:appScheme: "inkhash")`, `IssuedJoinCode`), das Suchen per Bonjour (`KennelDiscovery` hinter `KennelDiscovering`), der QR-Code des Beitrittslinks (`JoinQR`) und die Endpunkte des Kerns: Health, Anmelden und Abmelden, Beitreten, Gerätecodes, Passwort (`KennelClient`).
3. **In `InkhashCore` bleiben** die Routen des Moduls unter `/v1/apps/inkhash` in `APIClient`, jetzt auf `KennelClient.module("inkhash")`. Seine Fehler bleiben `APIError`, weil der Abgleich Konflikte aus dem Body liest. Die Fähigkeiten des Moduls liest `ModuleInfo` aus `KennelHealth.module("inkhash")`.
4. **Sitzungen:** Je Server ein Eintrag im Schlüsselbund wie bisher (Dienst `local.inkhash`, Schlüssel `server-<id>`), jetzt über `KennelSessionStore` als JSON mit Adresse, Account und Token. Ein Eintrag aus der Zeit davor enthält nur den Token; beim ersten Laden ergänzt die App Adresse und Account aus `setup.json` und schreibt ihn als JSON zurück. Niemand muss sich neu anmelden. Mehrere Server bleiben möglich.
5. Der Schlüssel des Tresors (ADR 0052) ist keine Sitzung; er bleibt in `SecretStore`.
6. Eine Adresse ohne Schema gilt jetzt als `http://…:8790` (KennelKit); vorher brauchte sie `http` oder `https`.

## Warum

Xoot und inkhash hatten dieselben Teile zweimal (teamCato ADR 0006). Mit KennelKit liest inkhash Codes, Links und Adressen genau wie Kennel und Xoot.

## Nicht

- Keine Fenster aus `KennelKitUI` in diesem Schritt; die kamen mit ADR 0074.
- Kein gemeinsamer Login mit anderen Apps.
