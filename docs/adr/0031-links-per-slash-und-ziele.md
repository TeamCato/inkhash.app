# 0031 Links über das `/`-Menü, Ziele werden geprüft

Status: angenommen

Ergänzt 0024 (Links im Text), 0027 (Links zu Notizen) und 0028 (Links auf der Seite).

## Entscheidung

**`/Link` im Text.** Das `/`-Menü hat „Link“. Die Wahl löscht die `/`-Zeile und fragt am Cursor nach Ziel und Text: zuerst das Ziel, dann das Label. Das Zielfeld ist dasselbe wie in der Formatleiste: Tippen schlägt Notizen des Workspace vor, alles andere ist eine Adresse. Bleibt das Label leer, wird es der Titel der Notiz oder der Host der Adresse (`example.com`, bei E-Mail die Adresse). Eingefügt wird das Label als Link, danach ein Leerzeichen ohne Link. Abbrechen lässt nichts zurück.

**Ziele nach außen gehen überall.** In Text und Handschrift darf ein Link auf eine andere Notiz, eine Webadresse oder eine E-Mail-Adresse zeigen. Ein getipptes Ziel wird vor dem Speichern normalisiert (`LinkTarget.normalize` im Kern):

- `example.com/a` wird `https://example.com/a`, `name@example.com` wird `mailto:name@example.com`
- `http://`, `https://`, `mailto:` und `inkhash://note/<id>` bleiben, die Notiz-ID kleingeschrieben
- andere Schemata (`ftp:`, `tel:`, `javascript:`), Leerzeichen im Ziel und leere Eingaben sind kein Link; das Feld sagt das, statt still etwas zu speichern
- `(` und `)` werden im Text als `%28`/`%29` geschrieben, weil das Markdown sie im Ziel nicht trägt (0024)

Ein getippter Titel, der genau eine Notiz trifft, verlinkt diese Notiz, wie bisher.

**Alte Ziele werden repariert.** Frühere Versionen speicherten auf der Seite getippte Adressen ohne Schema, die der Server ablehnt (API.md). Beim Lesen einer Seite wird ein solches Ziel normalisiert; lässt es sich nicht retten, fällt der Link weg, eine reine Linkfläche ganz.

## Warum

Das `/`-Menü ist der Ort, an dem man im Text alles Einfügbare sucht. Ohne Markierung gab es bisher keinen Weg zu einem Link außer `[[` (nur Notizen) oder Markdown von Hand. Die Prüfung gehört in den Kern, weil Text und Seite dieselben Ziele haben und der Server nur bestimmte Präfixe annimmt; eine Linkfläche mit `example.com` hätte den Abgleich der ganzen Notiz blockiert.

## Nicht

Keine Vorschau, kein Titel aus dem Netz für das Label, keine weiteren Schemata. Getipptes Markdown `[Text](Ziel)` wird weiter so übernommen, wie es dasteht.
