# Kavita reading server on Railway

The current template release is `v1.0.1`. It runs [Kavita](https://github.com/Kareadita/Kavita) `0.9.1.4` with the [dufs](https://github.com/sigoden/dufs) `0.47.0` upload manager behind a [Caddy](https://caddyserver.com) `2.11.9` gateway, all pinned by image digest.

Kavita is a self-hosted reading server for ebooks (EPUB, PDF), comics (CBZ, CBR, CB7) and manga, with a web reader, OPDS feeds, reading progress, collections and multiple users. Kavita reads books from folders on disk and has no upload feature of its own, so this template adds a browser upload manager that writes into the same Railway volume Kavita scans.

## Topology

| Service | Public | Source | Purpose |
| --- | --- | --- | --- |
| `Kavita Gateway` | yes, port 8080 | `caddy:2.11.9-alpine` by digest | Only public entry. Requires the generated gateway password for first-admin setup (`/api/account/register`) and for the upload manager (`/files/`). Every other request goes to Kavita, which uses its own login. |
| `Kavita` | no | this repository, `release-v1` branch, `Dockerfile` | Official `jvmilazz0/kavita:0.9.1` image by digest plus the dufs binary. Kavita listens on 5000 and dufs on 5001, both reachable only over Railway private networking. |

One 5 GB volume is mounted at `/data` on the Kavita service:

- `/data/config` is Kavita's configuration directory (SQLite database, generated JWT signing key, covers, logs and backups).
- `/data/library` is the book library. Everything you upload at `/files/` lands here.

The gateway is needed because a fresh Kavita lets whoever opens it first create the admin account. Kavita closes registration once an admin exists, but the gateway keeps that first step private and also protects uploads. Kavita's own login, API and OPDS keys work through the gateway unchanged.

## Deploy on Railway

1. Deploy the template. Nothing needs to be filled in: Railway generates `GATEWAY_PASSWORD`.
2. Copy `GATEWAY_USERNAME` (default `library-admin`) and `GATEWAY_PASSWORD` from the `Kavita Gateway` service variables.
3. Open the gateway's domain. Kavita shows its registration page. Enter the admin username, email (optional) and password you want, then submit. The browser asks for the gateway credentials once; enter the values from step 2.
4. Open `https://<your-domain>/files/` and sign in with the same gateway credentials. Create folders and upload books. Kavita expects one folder per series, for example `books/Author - Title/Title.epub` or `manga/Series Name/Series Name v01.cbz`.
5. In Kavita, open Server Settings, Libraries, Add Library. Pick a type (Book, Comic or Manga) and add a folder such as `/data/library/books`. Kavita scans the folder when the library is created. After later uploads, use Scan Library (folder watching may also pick up changes).

## Environment variables

`Kavita Gateway`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `8080` | Public gateway listener. |
| `GATEWAY_USERNAME` | `library-admin` | Username for setup and `/files/`. Letters, digits, `.`, `-`, `_`. |
| `GATEWAY_PASSWORD` | `${{secret(32)}}` | Generated password for setup and `/files/`. The gateway refuses to start with fewer than 16 characters. |
| `KAVITA_UPSTREAM` | `${{Kavita.RAILWAY_PRIVATE_DOMAIN}}:5000` | Private Kavita endpoint. |
| `UPLOAD_UPSTREAM` | `${{Kavita.RAILWAY_PRIVATE_DOMAIN}}:5001` | Private upload endpoint. |
| `GATEWAY_CONFIG` | pinned Caddyfile | Routing and authentication policy. Changing it changes the security boundary. |

`Kavita`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `5000` | Kavita listener used by Railway health checks (`/api/health`). |
| `KAVITA_DATA_DIR` | `/data` | Volume mount. Must stay `/data`; the image links `/kavita/config` to `/data/config`. |
| `UPLOAD_PORT` | `5001` | Private dufs listener. |

No other values are required. Email, OIDC and Kavita+ are optional Kavita features you can configure in its settings.

## Persistence and limits

The `/data` volume holds both the Kavita database and your books, so a redeploy or restart keeps accounts, libraries, reading progress, the JWT signing key and uploaded files. Railway attaches one volume per service, which is why config and library share it. Large comic or manga collections need a larger volume; resize it in Railway before it fills.

The image sets `DOTNET_gcServer=0` (workstation garbage collection). With ASP.NET's default server GC, Kavita sized its heap to Railway's container limits and held about 1.25 GB; with workstation GC it settled near 0.5 GB for the same workload. Large scans of big libraries use more memory and CPU while they run.

This is a single-instance deployment for individuals, families and small groups, not a high-availability setup. Back up the whole volume before upgrades. The upload manager can delete files under `/data/library`; anyone with the gateway password can manage the library.

## Local verification

```bash
bun install --frozen-lockfile
./scripts/verify.sh
cp .env.example .env   # set long random passwords
set -a; . ./.env; set +a
docker compose up -d --build
SMOKE_PHASE=initial ./scripts/smoke.sh
docker compose restart kavita
SMOKE_PHASE=restart ./scripts/smoke.sh
docker compose down -v
```

The smoke test checks that anonymous and wrong-password requests to setup and `/files/` get 401, creates the first admin through the gateway, confirms registration then closes, uploads two EPUB files through `/files/`, creates a library, runs a scan, and reads both books through Kavita's reader API. The restart phase checks that the login, library, files and series survived. Set `BASE_URL` to run it against a Railway deployment.

## Source and forks

The Railway template builds the `Kavita` service from `tech-progress/railway-template-kavita` on the `release-v1` branch with root directory `/`. To run your own fork, change the repository in `.railway/railway.ts`, create a `release-v1` branch, and authorize Railway's GitHub App for it.

## Upstream projects

- [Kavita](https://github.com/Kareadita/Kavita) ([website](https://www.kavitareader.com), [wiki](https://wiki.kavitareader.com))
- [dufs](https://github.com/sigoden/dufs)
- [Caddy](https://caddyserver.com)
