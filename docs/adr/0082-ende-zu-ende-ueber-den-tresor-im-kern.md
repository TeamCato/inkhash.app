# 0082 Ende-zu-Ende wieder, über den Tresor im Kern

Status: angenommen. Dominik am 2026-10-24 („In inkhash kann ich irgendwie keine verschlüsselten storages anlegen oder
nutzen!?“). Folgt teamCato ADR 0013 (jedes Modul kann Ende-zu-Ende) und Kennel ADR 0058 (inkhashs Tresor ist der im
Kern). Löst ab: ADR 0077 Punkt 5 Satz „Ein neuer Kennel-Workspace ist immer unverschlüsselt“, Punkt 8 und Punkt 9 (das
automatische Umwandeln), und teamCato ADR 0009 Punkt 10 für inkhash. Format und Vertrag aus ADR 0052 bleiben.

## Entscheidung

1. **Ein Tresor für alle Apps.** inkhash nimmt den Tresor aus KennelKit (`KennelVault`, Kennel ADR 0043): Anlegen,
   Öffnen mit Wiederherstellungsschlüssel oder Kopplung per QR, „Schlüssel nicht mehr da?“ mit Zurücksetzen über das
   Kennel-Passwort, Gerät hinzufügen. Die Fenster sind KennelKitUIs (`KennelVaultSetupView`, `KennelVaultUnlockView`,
   `KennelPairingOfferView`, `KennelVaultSection`). Ein Tresor aus Xoot öffnet sich in inkhash mit demselben Schlüssel;
   ein alter inkhash-Tresor (`inkhash-vault-v1`) öffnet weiter.
2. **Der Schlüssel** liegt in `KennelVaultKeyStore` (Dienst `local.inkhash`). Ein Schlüssel, den eine ältere inkhash-
   Version im Schlüsselbund hielt (`vault-<server>`), wird beim ersten Abgleich übernommen (`KennelVault.adopt`), ohne
   Eingabe. Der Abgleich bekommt ihn als `VaultKey` mit der `epoch` von inkhashs `/vault`; Notizen und Blobs bleiben im
   Format von ADR 0052.
3. **Neuer Workspace in Kennel** bietet „Ende-zu-Ende verschlüsseln“: nur beim Anlegen, danach fest (Kennel ADR 0026).
   Ohne offenen Tresor führt er zu „Tresor anlegen“ bzw. „Tresor öffnen“. Bestehende lesbare Workspaces bleiben, wie sie
   sind.
4. **Abgleich:** Verschlüsselte Workspaces gleichen wieder versiegelt ab (`SealedTransport`, Bindung mit `epoch`). Ist
   der Tresor hier zu, warten sie; die Statuszeile sagt dann „Verschlüsselte Workspaces gesperrt“ mit „Tresor öffnen …“,
   und der Workspace selbst „Zum Ansehen den Tresor öffnen.“ mit „Öffnen …“. Ohne verschlüsselten Workspace erwähnt
   inkhash den Tresor nur neutral auf der Seite „Kennel“.
5. **Kein Umwandeln mehr.** inkhash beginnt keine Umwandlung in unverschlüsselte Workspaces. Eine schon begonnene
   (`retiring`) läuft zu Ende, damit nichts halb liegen bleibt.
6. **Zeichen:** Schloss neben dem Namen des verschlüsselten Workspace, „· verschlüsselt“ in der Workspace-Wahl, im
   Abschnitt „Ort“ „Ende-zu-Ende verschlüsselt: nur deine Geräte können die Notizen lesen.“

## Warum

Ein Tresor, ein Wiederherstellungsschlüssel und ein Koppeln für alle Apps war die Bedingung, unter der Dominik
Verschlüsselung will (teamCato ADR 0013); mit dem Tresor im Kern fällt der Grund für ADR 0009 Punkt 10 weg.

## Nicht

- Kein geteilter Schlüsselbund aller teamCato-Apps ohne Provisioning-Profil auf dem Mac: bis dahin öffnet man den
  Tresor in inkhash einmal selbst (Kopplung per QR genügt).
- Kein Umschalten bestehender Workspaces; Verschlüsseln heißt: neuen verschlüsselten Workspace anlegen und Notizen
  hineinschieben.
