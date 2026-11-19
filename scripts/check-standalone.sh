#!/usr/bin/env bash
# Compare the monorepo template with its public distribution checkout.
set -euo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
standalone_dir="${1:?Usage: ./scripts/check-standalone.sh STANDALONE_DIR}"

[[ -d "${standalone_dir}/.git" ]] || { echo "Standalone Kavita repository not found." >&2; exit 1; }
[[ ! -e "${standalone_dir}/FINDINGS.md" ]] || { echo "FINDINGS.md must remain private to the monorepo." >&2; exit 1; }
if git -C "${standalone_dir}" log --all --format=%H -- FINDINGS.md | grep -q .; then
  echo "FINDINGS.md is reachable in the standalone history." >&2; exit 1
fi
diff -qr --exclude=.git --exclude=FINDINGS.md --exclude=node_modules "${template_root}" "${standalone_dir}"
echo "Kavita monorepo and standalone distribution files match."
