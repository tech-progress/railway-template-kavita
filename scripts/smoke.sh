#!/usr/bin/env bash
# Application-level smoke test through the public gateway.
#
#   SMOKE_PHASE=initial  boundary checks, first-admin setup through the gateway,
#                        book upload through /files, library scan, and reading
#                        the uploaded EPUB through Kavita's reader API.
#   SMOKE_PHASE=restart  after a Kavita restart: the admin login, library,
#                        scanned series, uploaded files and reader still work.
#
# Credentials come from the environment and are never printed.
set -euo pipefail

base_url="${BASE_URL:-http://127.0.0.1:13091}"
base_url="${base_url%/}"
phase="${SMOKE_PHASE:-initial}"
gateway_username="${GATEWAY_USERNAME:-library-admin}"
gateway_password="${GATEWAY_PASSWORD:?Set GATEWAY_PASSWORD}"
kavita_username="${KAVITA_USERNAME:-owner}"
kavita_password="${KAVITA_PASSWORD:?Set KAVITA_PASSWORD}"
library_name="Smoke Books"
library_folder="/data/library/smoke-books"
first_title="Railway Upload Book"
second_title="Railway Scan Book"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir:?}"' EXIT

gateway_auth="${work_dir}/gateway.netrc"
host="$(sed -E 's#^[a-z]+://([^/:]+).*#\1#' <<<"${base_url}")"
printf 'machine %s login %s password %s\n' "${host}" "${gateway_username}" "${gateway_password}" >"${gateway_auth}"
chmod 600 "${gateway_auth}"

fail() { echo "FAIL: $*" >&2; exit 1; }
status() { curl --silent --output /dev/null --write-out '%{http_code}' --path-as-is "$@"; }
gw() { curl --fail --silent --show-error --netrc-file "${gateway_auth}" "$@"; }
api() { curl --fail --silent --show-error -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' "$@"; }
urlpath() { jq -rn --arg value "$1" '$value|@uri'; }

wait_for_health() {
  for _ in $(seq 1 90); do
    [[ "$(status "${base_url}/healthz")" == 200 ]] && return 0
    sleep 2
  done
  fail "gateway /healthz did not reach Kavita within 180 seconds"
}

login() {
  curl --fail --silent --show-error -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg u "${kavita_username}" --arg p "${kavita_password}" '{username:$u,password:$p,apiKey:""}')" \
    "${base_url}/api/account/login" | jq -r '.token'
}

series_id() {
  api -X POST --data '{"statements":[],"combination":1,"sortOptions":{"sortField":1,"isAscending":true},"limitTo":0}' \
    "${base_url}/api/series/all-v2?PageNumber=1&PageSize=100" |
    jq -r --arg name "$1" --argjson library "${library_id}" '[.[]|select(.name==$name and .libraryId==$library)][0].id // empty'
}

read_book() {
  local id="$1" title="$2" chapter
  chapter="$(api "${base_url}/api/series/volumes?seriesId=${id}" | jq -r '.[0].chapters[0].id')"
  [[ "$(api "${base_url}/api/book/${chapter}/book-info" | jq -r '.bookTitle')" == "${title}" ]] || fail "book-info title mismatch for ${title}"
  api "${base_url}/api/book/${chapter}/book-page?page=0" | grep -Fq "<h1>${title}</h1>" || fail "reader did not return the page of ${title}"
}

wait_for_health

# Public boundary: setup and the upload manager need the gateway credential.
for path in /api/account/register /API/Account/Register /api/account/register/ //api/account/register /api/account/%72egister /api/./account/register; do
  code="$(status -X POST -H 'Content-Type: application/json' --data '{"username":"probe","password":"Probe-123456","email":""}' "${base_url}${path}")"
  [[ "${code}" == 401 ]] || fail "anonymous POST ${path} returned ${code}, expected 401"
done
for path in /files/ /files /FILES/ /%66iles/ "/files/?json"; do
  code="$(status "${base_url}${path}")"
  [[ "${code}" == 401 ]] || fail "anonymous GET ${path} returned ${code}, expected 401"
done
code="$(status -u "${gateway_username}:wrong-password-for-smoke" "${base_url}/files/")"
[[ "${code}" == 401 ]] || fail "wrong gateway password on /files/ returned ${code}, expected 401"
code="$(status -X PUT --data-binary 'x' "${base_url}/files/anonymous.txt")"
[[ "${code}" == 401 ]] || fail "anonymous upload returned ${code}, expected 401"
echo "boundary: anonymous and wrong-credential setup and upload requests return 401"

if [[ "${phase}" == initial ]]; then
  if [[ "$(curl --fail --silent --show-error "${base_url}/api/admin/exists")" == false ]]; then
    gw -X POST -H 'Content-Type: application/json' \
      --data "$(jq -nc --arg u "${kavita_username}" --arg p "${kavita_password}" '{username:$u,password:$p,email:""}')" \
      "${base_url}/api/account/register" >/dev/null
    echo "setup: first admin created through the gateway credential"
  fi
  [[ "$(curl --fail --silent --show-error "${base_url}/api/admin/exists")" == true ]] || fail "no admin exists after setup"
  code="$(status --netrc-file "${gateway_auth}" -X POST -H 'Content-Type: application/json' --data '{"username":"second","password":"Second-123456","email":""}' "${base_url}/api/account/register")"
  [[ "${code}" == 400 ]] || fail "second registration returned ${code}, expected 400"
  echo "setup: registration is closed once an admin exists"
fi

token="$(login)"
[[ -n "${token}" && "${token}" != null ]] || fail "Kavita login failed"
echo "login: Kavita admin login works through the gateway without the gateway credential"

if [[ "${phase}" == initial ]]; then
  python3 -I "${script_dir}/make-sample-epub.py" "${work_dir}/first.epub" "${first_title}"
  python3 -I "${script_dir}/make-sample-epub.py" "${work_dir}/second.epub" "${second_title}"
  folder="${library_folder#/data/library/}"
  [[ "$(gw --write-out '%{http_code}' --output /dev/null -T "${work_dir}/first.epub" "${base_url}/files/${folder}/$(urlpath "${first_title}")/$(urlpath "${first_title}").epub")" == 201 ]] || fail "first upload was not created"
  echo "upload: first EPUB stored through /files"

  library_id="$(api "${base_url}/api/library/libraries" | jq -r --arg name "${library_name}" '[.[]|select(.name==$name)][0].id // empty')"
  if [[ -z "${library_id}" ]]; then
    api -X POST --data "$(jq -nc --arg name "${library_name}" --arg folder "${library_folder}" '{id:0,name:$name,type:2,folders:[$folder],folderWatching:true,includeInDashboard:true,includeInSearch:true,manageCollections:true,manageReadingLists:true,allowScrobbling:false,allowMetadataMatching:false,enableMetadata:true,removePrefixForSortName:false,inheritWebLinksFromFirstChapter:false,defaultLanguage:"",metadataProvider:2,fileGroupTypes:[1,2,3,4],excludePatterns:[]}')" \
      "${base_url}/api/library/create" >/dev/null
    library_id="$(api "${base_url}/api/library/libraries" | jq -r --arg name "${library_name}" '[.[]|select(.name==$name)][0].id // empty')"
  fi
  [[ -n "${library_id}" ]] || fail "library ${library_name} was not created"
  echo "library: ${library_name} points at ${library_folder}"

  wait_for_series() {
    local title="$1" id=""
    for attempt in $(seq 1 60); do
      id="$(series_id "${title}")"
      [[ -n "${id}" ]] && break
      # Kavita skips a scan request while another scan of the library runs,
      # so ask again periodically until the uploaded book appears.
      (( attempt % 10 == 0 )) && api -X POST "${base_url}/api/library/scan?libraryId=${library_id}&force=true" >/dev/null
      sleep 2
    done
    [[ -n "${id}" ]] || fail "library scan did not find ${title}"
    read_book "${id}" "${title}"
    echo "scan: ${title} found by the library scan and readable"
  }
  wait_for_series "${first_title}"

  # Upload a second book after the first scan finished, then request a scan so
  # the result depends on Kavita scanning a file uploaded into an existing library.
  [[ "$(gw --write-out '%{http_code}' --output /dev/null -T "${work_dir}/second.epub" "${base_url}/files/${folder}/$(urlpath "${second_title}")/$(urlpath "${second_title}").epub")" == 201 ]] || fail "second upload was not created"
  echo "upload: second EPUB stored through /files after the library existed"
  api -X POST "${base_url}/api/library/scan?libraryId=${library_id}&force=true" >/dev/null
  wait_for_series "${second_title}"
else
  library_id="$(api "${base_url}/api/library/libraries" | jq -r --arg name "${library_name}" '[.[]|select(.name==$name)][0].id // empty')"
  [[ -n "${library_id}" ]] || fail "library ${library_name} did not survive restart"
  listing="$(gw "${base_url}/files/${library_folder#/data/library/}/?json")"
  for title in "${first_title}" "${second_title}"; do
    jq -e --arg name "${title}" '.paths|any(.name==$name)' <<<"${listing}" >/dev/null || fail "uploaded folder ${title} did not survive restart"
    id="$(series_id "${title}")"
    [[ -n "${id}" ]] || fail "series ${title} did not survive restart"
    read_book "${id}" "${title}"
  done
  echo "restart: login, library, uploaded files, scanned series and reader survived"
fi

echo "PASS: Kavita ${phase} smoke through ${base_url}"
