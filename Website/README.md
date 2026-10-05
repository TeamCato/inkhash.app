# Website

Statischer Onepager für inkhash. Kein Build, kein JavaScript.

- `index.html` — die Seite. Farben spiegeln `Ink` in `App/Shared/Theme.swift` und ADR 0011: hell, Anthrazit, ein dezentes Blau.
- `mark.svg` — Bildmarke, aus denselben Strichen wie `InkhashMark` berechnet.
- `app-icon.png` — Kopie von `AppIcon.png`, für `apple-touch-icon`.

Ändert sich die Marke oder das Icon in der App, beides hier nachziehen. Die Verwaltungsseite des Servers (`Server/admin/page.ts`) trägt dieselbe Palette und `mark.svg` inline, weil ihre CSP keine Bilder nachlädt; dort ebenfalls nachziehen.

Lokal ansehen:

```sh
python3 -m http.server 8790 --directory Website
```

Offen: App-Store-Links für iPad und Mac (stehen als „bald im App Store“ ohne Ziel), GitHub-Repo ist noch privat.
