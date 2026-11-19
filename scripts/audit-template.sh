#!/usr/bin/env bash
# Audit Railway's stored serializedConfig against the checked-in contract.
# Never prints variable values.
set -euo pipefail

template_id="${1:?Usage: ./scripts/audit-template.sh TEMPLATE_ID [EXPECTED_STATUS]}"
expected_status="${2:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$(railway api 'query Audit($id:String!){template(id:$id){name status serializedConfig}}' --var "id=${template_id}" --compact)"
graph="$(cd "${root}" && ./node_modules/.bin/railway-iac-ts .railway/railway.ts </dev/null)"
failures=0
check() { local label="$1"; shift; if ! "$@"; then echo "mismatch: ${label}" >&2; failures=$((failures + 1)); fi; }
eq() { [[ "$1" == "$2" ]]; }

check "template name" eq "$(jq -r '.data.template.name' <<<"${template}")" "Kavita reading server"
[[ -z "${expected_status}" ]] || check "template status" eq "$(jq -r '.data.template.status' <<<"${template}")" "${expected_status}"
desired_names="$(jq -r '[.graph.resources[]|select(.type=="service")|.name]|sort|join("\n")' <<<"${graph}")"
check "service set" eq "$(jq -r '.data.template.serializedConfig.services|map(.name)|sort|join("\n")' <<<"${template}")" "${desired_names}"
check "service set literal" eq "${desired_names}" $'Kavita\nKavita Gateway'

while IFS= read -r name; do
  desired="$(jq -c --arg n "${name}" '.graph.resources[]|select(.type=="service" and .name==$n)' <<<"${graph}")"
  actual="$(jq -c --arg n "${name}" '[.data.template.serializedConfig.services[]|select(.name==$n)][0]' <<<"${template}")"
  if [[ "$(jq -r '.source.image // ""' <<<"${desired}")" != "" ]]; then
    check "${name} image" eq "$(jq -r '.source.image // ""' <<<"${actual}")" "$(jq -r '.source.image' <<<"${desired}")"
    check "${name} no repo fields" eq "$(jq -r '[.source.repo,.source.branch,.source.rootDirectory]|map(select(.!=null and .!=""))|length' <<<"${actual}")" 0
  else
    check "${name} repo" eq "$(jq -r '(.source.repo // "")|sub("^https://github.com/";"")|sub("\\.git$";"")' <<<"${actual}")" "tech-progress/railway-template-kavita"
    check "${name} branch" eq "$(jq -r '.source.branch // ""' <<<"${actual}")" release-v1
    check "${name} root" eq "$(jq -r '.source.rootDirectory // ""' <<<"${actual}")" /
    check "${name} no image" eq "$(jq -r '.source.image // ""' <<<"${actual}")" ""
    check "${name} builder" eq "$(jq -r '.build.builder // ""' <<<"${actual}")" DOCKERFILE
    check "${name} dockerfile" eq "$(jq -r '.build.dockerfilePath // ""' <<<"${actual}")" Dockerfile
  fi
  for field in startCommand healthcheckPath healthcheckTimeout; do
    check "${name} ${field}" eq "$(jq -r --arg f "${field}" '.deploy[$f] // ""' <<<"${actual}")" "$(jq -r --arg f "${field}" '.deploy[$f] // ""' <<<"${desired}")"
  done
  check "${name} one replica" eq "$(jq -r '.deploy.numReplicas // 1' <<<"${actual}")" 1
  check "${name} restart policy" eq "$(jq -r '[.deploy.restartPolicyType, .deploy.restartPolicyMaxRetries]|@tsv' <<<"${actual}")" $'ON_FAILURE\t10'
  check "${name} variable keys" eq "$(jq -r '(.variables//{})|keys|sort|join(",")' <<<"${actual}")" "$(jq -r --arg n "${name}" '.[$n]|keys|sort|join(",")' "${root}/template-defaults.json")"
  while IFS= read -r key; do
    check "${name} ${key} default" eq "$(jq -r --arg k "${key}" '.variables[$k].defaultValue // "__MISSING__"' <<<"${actual}")" "$(jq -r --arg n "${name}" --arg k "${key}" '.[$n][$k]' "${root}/template-defaults.json")"
    check "${name} ${key} required" eq "$(jq -r --arg k "${key}" '.variables[$k].isOptional // false' <<<"${actual}")" false
    check "${name} ${key} description" eq "$(jq -r --arg k "${key}" '.variables[$k].description // ""' <<<"${actual}")" "$(jq -r --arg n "${name}" --arg k "${key}" '.[$n][$k]' "${root}/template-descriptions.json")"
  done < <(jq -r --arg n "${name}" '.[$n]|keys[]' "${root}/template-defaults.json")
  if jq -e --arg n "${name}" '.[$n]!=null' "${root}/template-volumes.json" >/dev/null; then
    check "${name} volume" eq "$(jq -c '[((.volumeMounts//{})|length), ((.volumeMounts//{})|to_entries[0].value|{mountPath,sizeMB})]' <<<"${actual}")" "$(jq -c --arg n "${name}" '[1, .[$n]]' "${root}/template-volumes.json")"
  else
    check "${name} no volume" eq "$(jq -r '(.volumeMounts//{})|length' <<<"${actual}")" 0
  fi
  if jq -e --arg n "${name}" '.[$n].publicPort!=null' "${root}/template-networking.json" >/dev/null; then
    check "${name} domain" eq "$(jq -c '[((.networking.serviceDomains//{})|length), .networking.serviceDomains["<hasDomain>"].port]' <<<"${actual}")" "$(jq -c --arg n "${name}" '[1, .[$n].publicPort]' "${root}/template-networking.json")"
  else
    check "${name} private" eq "$(jq -r '(.networking.serviceDomains//{})|length' <<<"${actual}")" 0
  fi
  check "${name} no tcp proxy" eq "$(jq -r '(.networking.tcpProxies//{})|length' <<<"${actual}")" 0
  # Any other networking entry (custom domains or a future ingress type) fails.
  check "${name} no other ingress" eq "$(jq -r '[(.networking//{})|to_entries[]|select(.key!="serviceDomains" and .key!="tcpProxies")|select(.value!=null and .value!={} and .value!=[])]|length' <<<"${actual}")" 0
done <<<"${desired_names}"

(( failures == 0 )) || { echo "Kavita template audit failed with ${failures} mismatch(es)." >&2; exit 1; }
echo "Template ${template_id} matches the Kavita source, gateway, variable, volume, and networking contract."
