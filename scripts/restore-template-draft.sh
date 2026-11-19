#!/usr/bin/env bash
# Restore the generated Railway draft to the checked-in contract: sources,
# start commands, health checks, variable defaults (including the generated
# gateway password), the single volume, and the gateway-only public domain.
set -euo pipefail

template_id="${1:?Usage: ./scripts/restore-template-draft.sh TEMPLATE_ID WORKSPACE_ID}"
workspace_id="${2:?Usage: ./scripts/restore-template-draft.sh TEMPLATE_ID WORKSPACE_ID}"
template_name="Kavita reading server"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
token="$(jq -r '.user.accessToken' "${RAILWAY_CONFIG_PATH:-${HOME}/.railway/config.json}")"
graph="$(cd "${root}" && ./node_modules/.bin/railway-iac-ts .railway/railway.ts </dev/null)"
draft="$(railway api 'query Draft($id:String!){template(id:$id){serializedConfig}}' --var "id=${template_id}" --compact)"

variables="$(jq -nc --argjson draft "${draft}" --argjson graph "${graph}" \
  --slurpfile defaults "${root}/template-defaults.json" --slurpfile descriptions "${root}/template-descriptions.json" \
  --slurpfile volumes "${root}/template-volumes.json" --slurpfile networking "${root}/template-networking.json" \
  --arg id "${template_id}" --arg workspaceId "${workspace_id}" --arg name "${template_name}" '
  ($graph.graph.resources|map(select(.type=="service"))|map({key:.name,value:.})|from_entries) as $desired
  | $draft.data.template.serializedConfig as $config
  | if (($config.services|map(.name)|sort)!=($desired|keys|sort)) then error("Draft service set mismatch") else
      reduce ($config.services|to_entries[]) as $s ($config;
        $desired[$s.value.name] as $d
        | if $d.source.image != null then
            .services[$s.key].source = {image:$d.source.image}
            | del(.services[$s.key].build)
          else
            .services[$s.key].source = {repo:$d.source.repo, branch:$d.source.branch, rootDirectory:$d.source.rootDirectory}
            | .services[$s.key].build = ((.services[$s.key].build // {}) + $d.build)
          end
        | .services[$s.key].deploy.startCommand = ($d.deploy.startCommand // null)
        | .services[$s.key].deploy.healthcheckPath = ($d.deploy.healthcheckPath // null)
        | .services[$s.key].deploy.healthcheckTimeout = ($d.deploy.healthcheckTimeout // null)
        | (.services[$s.key].variables // {}) as $existing
        | .services[$s.key].variables = reduce (($defaults[0][$s.value.name] // {})|to_entries[]) as $v ({};
            .[$v.key] = (($existing[$v.key] // {}) + {defaultValue:$v.value, isOptional:false, description:($descriptions[0][$s.value.name][$v.key] // "")}))
        | if $volumes[0][$s.value.name] != null then
            if ((.services[$s.key].volumeMounts // {})|length) != 1 then error("Expected exactly one draft volume mount for "+$s.value.name) else
              reduce (.services[$s.key].volumeMounts|keys[]) as $m (.;
                .services[$s.key].volumeMounts[$m].mountPath = $volumes[0][$s.value.name].mountPath
                | .services[$s.key].volumeMounts[$m].sizeMB = $volumes[0][$s.value.name].sizeMB)
            end
          else .services[$s.key].volumeMounts = {} end
        | if $networking[0][$s.value.name].publicPort != null then
            .services[$s.key].networking.serviceDomains = {"<hasDomain>":{port:$networking[0][$s.value.name].publicPort}}
          else .services[$s.key].networking.serviceDomains = {} end
        | .services[$s.key].networking.tcpProxies = {})
      | {id:$id, input:{name:$name, workspaceId:$workspaceId, serializedConfig:.}}
    end')"

request="$(jq -nc --argjson variables "${variables}" --arg query 'mutation Update($id:String!,$input:TemplateUpsertConfigInput!){templateUpsertConfig(id:$id,input:$input){id code}}' '{query:$query,variables:$variables}')"
response="$(curl --compressed --fail --silent --show-error https://backboard.railway.com/graphql/internal -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' --data-binary "${request}")"
jq -e '.data.templateUpsertConfig.id!=null and ((.errors//[])|length==0)' <<<"${response}" >/dev/null || { jq -c '.errors' <<<"${response}" >&2; exit 1; }

settings="$(jq -nc --arg id "${template_id}" --arg workspaceId "${workspace_id}" --arg name "${template_name}" --arg query 'mutation Settings($id:String!,$input:TemplateUpsertSettingsInput!){templateUpsertSettings(id:$id,input:$input){id name}}' '{query:$query,variables:{id:$id,input:{name:$name,workspaceId:$workspaceId}}}')"
response="$(curl --compressed --fail --silent --show-error https://backboard.railway.com/graphql/internal -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' --data-binary "${settings}")"
jq -e --arg name "${template_name}" '.data.templateUpsertSettings.name==$name and ((.errors//[])|length==0)' <<<"${response}" >/dev/null || { jq -c '.errors' <<<"${response}" >&2; exit 1; }
echo "Restored Kavita draft ${template_id}."
