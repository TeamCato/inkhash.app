# 0040 Kein Reverse-Proxy im Lieferumfang

Status: angenommen

## Entscheidung

Inkhash liefert den Server für das Heimnetz aus: `http://<lan-adresse>:8787`. Release-Paket und Compose-Datei enthalten keinen Reverse-Proxy, keine Caddyfile und keine Domain-Einstellung. `docs/DEPLOY.md` beschreibt nur die Einrichtung im Heimnetz.

Zugriff von außen, TLS, VPN oder Reverse-Proxy richtet der Betreiber mit seinem eigenen Setup ein. Der Server unterstützt das weiter über `INKHASH_TRUSTED_PROXIES` (ADR 0038). Die Compose-Datei vertraut dem Host, damit ein Proxy dort ohne Änderung funktioniert; `INKHASH_TRUSTED_PROXIES` in `.env` überschreibt das.

Ersetzt den Caddy-Teil von ADR 0039.

## Warum

Wer einen Server selbst betreibt, hat meist schon einen Reverse-Proxy oder ein VPN. Ein mitgelieferter Caddy würde damit um die Ports 80 und 443 konkurrieren, und Anleitungen für Tailscale, Caddy, nginx, Cloudflare und DS-Lite veralten, ohne dass wir sie testen können.

## Nicht

Kein TLS im Server, kein mitgelieferter Proxy, keine Anleitung für einzelne Proxys oder Router.
