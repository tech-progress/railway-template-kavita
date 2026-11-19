# Publishing

The current template release is `v1.0.0`. The `Kavita` service builds `tech-progress/railway-template-kavita` from `release-v1` with root directory `/`; the gateway runs the pinned Caddy image.

1. `bun install --frozen-lockfile` and `./scripts/verify.sh`.
2. Clean local build and smoke: `docker compose down -v`, `docker compose up -d --build`, `SMOKE_PHASE=initial ./scripts/smoke.sh`, `docker compose restart kavita`, `SMOKE_PHASE=restart ./scripts/smoke.sh`, then `docker compose down -v`.
3. Sync the public distribution repository (everything except `FINDINGS.md` and `node_modules`), run `./scripts/check-standalone.sh <checkout>`, tag `v<version>`, and fast-forward `release-v1`.
4. Create a project named `kavita-reading-server`, link it, and run `KAVITA_SOURCE_GATEWAY_PASSWORD=<fresh random value> railway config apply --yes`. Do not attach a domain to the source project.
5. `railway templates create --project <PROJECT_ID> --environment <ENVIRONMENT_ID> --json`, then `./scripts/restore-template-draft.sh <TEMPLATE_ID> <WORKSPACE_ID>` and `./scripts/audit-template.sh <TEMPLATE_ID>`.
6. Deploy the stored `serializedConfig` with `templateDeployV2` into a disposable project. Read `GATEWAY_PASSWORD` from the deployed gateway into a 0600 file, then run both smoke phases with `BASE_URL=https://<gateway domain>` around a Kavita restart. Check replicas, metrics, and that no credential appears in the logs.
7. Publish:

```bash
railway templates publish <TEMPLATE_ID> \
  --category Other \
  --description "Kavita ebook, comic and manga server with browser uploads and storage" \
  --readme-file MARKETPLACE.md \
  --json
```

8. `./scripts/audit-template.sh <TEMPLATE_ID> PUBLISHED`, then from the repository root `scripts/sync-template-marketplace.sh kavita-reading-server` and `scripts/audit-template-marketplace.sh kavita-reading-server`.
9. Stop and delete the source and verification projects, prove zero running instances, and tag `kavita-reading-server-v<version>` in the monorepo.
