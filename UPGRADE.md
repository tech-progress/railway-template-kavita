# Upgrades

1. Back up the `/data` volume. `config/` holds the Kavita database and settings; `library/` holds your books.
2. Read the [Kavita release notes](https://github.com/Kareadita/Kavita/releases) for migration notes.
3. Update the Kavita tag and digest together in `Dockerfile` (and the dufs pin if needed), bump `VERSION` and `CHANGELOG.md`.
4. Run `./scripts/verify.sh`, then the local stack with `SMOKE_PHASE=initial ./scripts/smoke.sh`, restart Kavita, and run `SMOKE_PHASE=restart ./scripts/smoke.sh`.
5. Tag the release, fast-forward `release-v1`, and let Railway rebuild the Kavita service.

Kavita runs database migrations on start and cannot be downgraded in place; restore the volume backup to roll back.
