# Website

Statischer Onepager für inkhash. Kein Build, kein JavaScript.

- `index.html` — die Seite. Farben spiegeln `Ink` in `App/Shared/Theme.swift` und ADR 0066: Deep Blue auf warmem Papier, Blue Gray, Sage Green, Warm Sand.
- `mark.svg` — Bildmarke, aus denselben Strichen wie `InkhashMark` berechnet.
- `app-icon.png` — Kopie von `AppIcon.png`, für `apple-touch-icon`.

Ändert sich die Marke oder das Icon in der App, beides hier nachziehen. Die Verwaltungsseite gehört jetzt Kennel (ADR 0067).

Lokal ansehen:

```sh
python3 -m http.server 8790 --directory Website
```

Offen: App-Store-Links für iPad und Mac (stehen als „bald im App Store“ ohne Ziel).
