#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
terraform_dir="$project_root/terraform"

# shellcheck disable=SC1091
source "$project_root/lib/load-env.sh"
load_env_file "$project_root/.env"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage: mise run tf -- <terraform args...>

Runs terraform inside terraform/ with .env loaded.
Examples:
  mise run tf -- init
  mise run tf -- plan
  mise run tf -- apply
EOF
  exit 0
fi

terraform_cmd=()
if command -v terraform >/dev/null 2>&1; then
  terraform_cmd=(terraform)
elif command -v mise >/dev/null 2>&1 && (cd "$project_root" && mise where terraform >/dev/null 2>&1); then
  terraform_cmd=(mise exec -- terraform)
else
  printf 'Error: terraform not found. Run mise run setup first.\n' >&2
  exit 1
fi

[ -d "$terraform_dir" ] || {
  printf 'Error: missing terraform directory: %s\n' "$terraform_dir" >&2
  exit 1
}

(
  cd "$terraform_dir"
  "${terraform_cmd[@]}" "$@"
)
