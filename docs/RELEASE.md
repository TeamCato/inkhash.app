# Server veröffentlichen

Für Maintainer. Betreiber lesen `docs/DEPLOY.md`. Hintergrund: ADR 0039.

```sh
git tag server-v0.1.0
git push origin server-v0.1.0
```

Die Action `Server release` testet, baut das Paket (`deploy/package.sh`), schiebt das Image nach GHCR und legt das GitHub-Release an. Lokal baut `make server-package VERSION=0.1.0` dasselbe Paket nach `.build/release/`. Beim ersten Mal das Paket `inkhash-server` auf GitHub unter Packages auf öffentlich stellen, sonst braucht `docker pull` eine Anmeldung.

## Container aus dem Quellcode

Im Repo `docker compose up --build`, der Setup-Token steht in `docker compose logs inkhash`. Ein Volume aus einer älteren Version gehört noch root und muss einmal umgestellt werden: `docker compose run --rm -u root inkhash chown -R node:node /data` (P-023).
