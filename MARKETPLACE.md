# Deploy and Host Kavita on Railway

Kavita is a self-hosted reading server for ebooks, comics and manga. This template runs Kavita 0.9.1.4 privately, adds a browser upload manager for your library, and puts a password-protected gateway in front of first-time setup and uploads.

## About Hosting Kavita

Kavita reads books from folders on disk and has no built-in upload, so this template adds [dufs](https://github.com/sigoden/dufs) at `/files/` to upload into the same volume Kavita scans. One 5 GB volume at `/data` holds both the Kavita database (`/data/config`) and your books (`/data/library`), so accounts, libraries, reading progress and files survive restarts and redeploys.

The Caddy gateway is the only public service. It asks for a generated password (`GATEWAY_USERNAME` and `GATEWAY_PASSWORD` on the `Kavita Gateway` service) before anyone can create the first Kavita admin or open the upload manager. Everything else uses Kavita's own login, so the web reader, mobile apps and OPDS feeds work normally.

After deploying: open the domain, create your admin account (the browser asks for the gateway credentials once), upload books at `/files/` in one folder per series, then add a library in Kavita pointing at a folder such as `/data/library/books`.

## Why Deploy Kavita on Railway

- No first-visit takeover: admin registration stays behind the generated gateway password.
- Upload books, comics and manga from a browser instead of copying files to a server.
- Pinned image digests for Kavita, dufs and Caddy, with health checks and a persistent volume.

## Common Use Cases

- A private ebook library with a web reader for you and your family.
- Reading comics and manga across devices with synced progress.
- Serving an OPDS catalog to reading apps on phones and e-readers.

## Dependencies for Kavita Hosting

The template uses two services and one Railway volume. No database or external account is needed.

### Deployment Dependencies

- [Kavita](https://github.com/Kareadita/Kavita) provides the library scanner, reader, users and OPDS.
- [dufs](https://github.com/sigoden/dufs) provides the browser upload manager for the library folder.
- [Caddy](https://caddyserver.com) provides the public gateway and its Basic Auth on setup and uploads.
- [Railway](https://railway.com) provides builds, private networking, HTTPS and the persistent volume.
