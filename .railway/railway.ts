import { defineRailway, github, group, project, service, volume } from "railway/iac";
import defaults from "../template-defaults.json";

const KAVITA_SOURCE = github("tech-progress/railway-template-kavita", { branch: "release-v1", rootDirectory: "/" });
const CADDY_IMAGE = "caddy:2.11.9-alpine@sha256:0bbb055bda6793c999bde78b1b5ce3e89f829fb031af2cf50056ea1246559fee";

// Same script as compose.yaml: validate the credential, hash it from stdin,
// drop the plaintext, render the pinned policy, and run Caddy.
export const GATEWAY_START =
  `/bin/sh -ec 'case "$GATEWAY_USERNAME" in ""|*[!A-Za-z0-9._-]*) echo "GATEWAY_USERNAME must use letters, digits, dot, dash or underscore." >&2; exit 64;; esac; ` +
  `[ "$(printf "%s" "$GATEWAY_PASSWORD" | wc -c)" -ge 16 ] || { echo "GATEWAY_PASSWORD must have at least 16 characters." >&2; exit 64; }; ` +
  `password_hash="$(printf "%s" "$GATEWAY_PASSWORD" | caddy hash-password)"; unset GATEWAY_PASSWORD; ` +
  `printf "%s\\n" "$GATEWAY_CONFIG" | sed -e "s|__USERNAME__|$GATEWAY_USERNAME|g" -e "s|__PASSWORD_HASH__|$password_hash|g" -e "s|__KAVITA__|$KAVITA_UPSTREAM|g" -e "s|__UPLOADS__|$UPLOAD_UPSTREAM|g" >/tmp/Caddyfile; ` +
  `unset GATEWAY_CONFIG; exec caddy run --config /tmp/Caddyfile --adapter caddyfile'`;

export default defineRailway((ctx) => {
  // Disposable source projects receive a concrete password from the publisher
  // (KAVITA_SOURCE_GATEWAY_PASSWORD). The marketplace draft is restored to the
  // ${{secret(32)}} default in template-defaults.json.
  const gatewayPassword = process.env.KAVITA_SOURCE_GATEWAY_PASSWORD ?? "";
  const data = volume("Kavita Data", { sizeMB: 5_000 });
  const kavita = service("Kavita", {
    source: KAVITA_SOURCE,
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile", watchPatterns: ["/Dockerfile", "/railway-entrypoint.sh"] },
    healthcheck: "/api/health",
    healthcheckTimeout: 600,
    volumeMounts: { "/data": data },
    env: { ...defaults.Kavita },
  });
  const gateway = service("Kavita Gateway", {
    source: { image: CADDY_IMAGE },
    start: GATEWAY_START,
    healthcheck: "/healthz",
    healthcheckTimeout: 600,
    env: { ...defaults["Kavita Gateway"], GATEWAY_PASSWORD: gatewayPassword },
  });
  return project("kavita-reading-server", { resources: [group("Reading server", [gateway, kavita, data])] });
});
