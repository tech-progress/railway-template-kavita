#!/bin/bash
# Starts Kavita and the private dufs upload server side by side.
# Both share the Railway volume mounted at /data:
#   /data/config   Kavita database, settings, covers, logs (via /kavita/config)
#   /data/library  books uploaded through dufs and scanned by Kavita
# If either process exits, the other is stopped and the container exits so
# Railway restarts the service.
set -euo pipefail

data_dir="${KAVITA_DATA_DIR:-/data}"
if [[ "${data_dir}" != /data ]]; then
  echo "KAVITA_DATA_DIR must be /data; the image links /kavita/config to /data/config." >&2
  exit 64
fi
mkdir -p "${data_dir}/config" "${data_dir}/library"

dufs "${data_dir}/library" \
  --bind 0.0.0.0 --bind :: \
  --port "${UPLOAD_PORT:-5001}" \
  --path-prefix files \
  --allow-upload --allow-delete --allow-search --allow-archive \
  --hidden '.*' &
dufs_pid=$!

cd /kavita
/bin/bash /entrypoint.sh &
kavita_pid=$!

stop() {
  kill -TERM "${kavita_pid}" "${dufs_pid}" 2>/dev/null || true
}
trap stop TERM INT

status=0
wait -n "${kavita_pid}" "${dufs_pid}" || status=$?
stop
wait "${kavita_pid}" 2>/dev/null || true
wait "${dufs_pid}" 2>/dev/null || true
exit "${status}"
