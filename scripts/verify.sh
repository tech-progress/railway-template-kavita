#!/usr/bin/env bash
# Static verification: files, version, pins, IaC graph, and Compose/Railway parity.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for file in .dockerignore .env.example .gitignore .railway/railway.ts CHANGELOG.md Dockerfile LICENSE_REVIEW.md MARKETPLACE.md PUBLISHING.md README.md SUPPORT.md UPGRADE.md VERSION bun.lock compose.yaml package.json railway-entrypoint.sh template-defaults.json template-descriptions.json template-networking.json template-volumes.json scripts/audit-template.sh scripts/check-standalone.sh scripts/make-sample-epub.py scripts/restore-template-draft.sh scripts/smoke.sh; do
  [[ -f "${root}/${file}" ]] || fail "missing ${file}"
done

version="$(<"${root}/VERSION")"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION is not SemVer"
grep -Eq "^## ${version//./\\.} - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "${root}/CHANGELOG.md" || fail "CHANGELOG has no entry for ${version}"
for file in README.md PUBLISHING.md; do grep -Fq "current template release is \`v${version}\`" "${root}/${file}" || fail "${file} does not name v${version}"; done

for file in "${root}"/template-*.json; do jq empty "${file}"; done
for file in "${root}"/scripts/*.sh "${root}/railway-entrypoint.sh"; do bash -n "${file}"; done
python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "${root}/scripts/make-sample-epub.py"

kavita_pin='FROM jvmilazz0/kavita:0.9.1@sha256:31181a32f0dda73cae68721867028a7253d57881b58bea5754cd9e578e75421a'
dufs_pin='FROM sigoden/dufs:v0.47.0@sha256:e5152c04e41d5a9d785546278b632bf035c8a08c52d7e8d35f4b59681f5ff35a AS dufs'
caddy_pin='caddy:2.11.9-alpine@sha256:0bbb055bda6793c999bde78b1b5ce3e89f829fb031af2cf50056ea1246559fee'
grep -Fxq "${kavita_pin}" "${root}/Dockerfile" || fail "Kavita pin"
grep -Fxq "${dufs_pin}" "${root}/Dockerfile" || fail "dufs pin"
! grep -Eq '^VOLUME' "${root}/Dockerfile" || fail "Railway rejects Dockerfile VOLUME"
grep -Eq '^ENV .*DOTNET_gcServer=0' "${root}/Dockerfile" || fail "workstation GC keeps Kavita memory near 0.5 GB on Railway"
grep -Fq "image: ${caddy_pin}" "${root}/compose.yaml" || fail "Compose Caddy pin"

graph="$(cd "${root}" && ./node_modules/.bin/railway-iac-ts .railway/railway.ts </dev/null)"
jq -e '.ok==true' <<<"${graph}" >/dev/null || fail "IaC graph did not compile"
jq -e '([.graph.resources[]|select(.type=="service")|.name]|sort)==["Kavita","Kavita Gateway"] and ([.graph.resources[]|select(.type=="volume")]|length)==1' <<<"${graph}" >/dev/null || fail "IaC service or volume set"
jq -e '.graph.resources[]|select(.name=="Kavita")|.source.repo=="tech-progress/railway-template-kavita" and .source.branch=="release-v1" and .source.rootDirectory=="/" and .build.builder=="DOCKERFILE" and .deploy.healthcheckPath=="/api/health"' <<<"${graph}" >/dev/null || fail "Kavita source or health check"
jq -e --arg img "${caddy_pin}" '.graph.resources[]|select(.name=="Kavita Gateway")|.source.image==$img and .deploy.healthcheckPath=="/healthz"' <<<"${graph}" >/dev/null || fail "gateway image or health check"
jq -e '[.graph.resources[]|select(.name=="Kavita Gateway")|.variables.GATEWAY_PASSWORD.value]==[""]' <<<"${graph}" >/dev/null || fail "IaC must not derive a gateway password without KAVITA_SOURCE_GATEWAY_PASSWORD"
jq -e '."Kavita Gateway".GATEWAY_PASSWORD=="${{secret(32)}}"' "${root}/template-defaults.json" >/dev/null || fail "marketplace gateway password must be generated"

# Compose and Railway run the same gateway script and policy.
compose_json="$(GATEWAY_PASSWORD=verify-only-password KAVITA_PASSWORD=verify docker compose -f "${root}/compose.yaml" config --format json)"
[[ "$(jq -r '.services.gateway.command[0]' <<<"${compose_json}" | sed 's/\$\$/$/g')" == "$(jq -r '.graph.resources[]|select(.name=="Kavita Gateway").deploy.startCommand|ltrimstr("/bin/sh -ec '"'"'")|rtrimstr("'"'"'")' <<<"${graph}")" ]] || fail "Compose and Railway gateway start commands differ"
[[ "$(jq -r '.services.gateway.environment.GATEWAY_CONFIG|rtrimstr("\n")' <<<"${compose_json}")" == "$(jq -r '."Kavita Gateway".GATEWAY_CONFIG' "${root}/template-defaults.json")" ]] || fail "Compose and Railway gateway policies differ"
for key in PORT KAVITA_DATA_DIR UPLOAD_PORT; do
  [[ "$(jq -r --arg k "${key}" '.services.kavita.environment[$k]' <<<"${compose_json}")" == "$(jq -r --arg k "${key}" '.Kavita[$k]' "${root}/template-defaults.json")" ]] || fail "Compose Kavita ${key} differs"
done

for heading in '# Deploy and Host' '## About Hosting' '## Why Deploy' '## Common Use Cases' '## Dependencies for' '### Deployment Dependencies'; do
  grep -q "^${heading}" "${root}/MARKETPLACE.md" || fail "MARKETPLACE.md lacks ${heading}"
done
description="$(sed -n 's/^  --description "\(.*\)" \\$/\1/p' "${root}/PUBLISHING.md")"
(( ${#description} >= 45 && ${#description} <= 75 )) || fail "marketplace description must be 45-75 characters"
echo "Kavita template structure, pins, gateway parity, IaC graph and marketplace copy are valid."
