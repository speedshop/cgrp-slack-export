#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
archive_dir="$project_root/archive"
zip_path="$project_root/railsperf-export-latest.zip"
tar_path="$project_root/railsperf-export-latest.tar"

# shellcheck disable=SC1091
source "$project_root/lib/load-env.sh"
load_env_file "$project_root/.env"

run_build=0
for arg in "$@"; do
  case "$arg" in
    --build)
      run_build=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: mise run upload -- [--build]

Creates railsperf-export-latest.zip (or .tar fallback) from archive/ and uploads it.

Upload methods (in order):
  1) R2_PRESIGNED_PUT_URL + curl
  2) aws CLI direct upload to R2 (credentials from .env)

Expected env vars for aws mode:
  R2_ACCOUNT_ID (or CLOUDFLARE_ACCOUNT_ID)
  R2_BUCKET (default: railsperf-exports)
  R2_OBJECT_KEY (default: railsperf-export-latest.zip)
  R2_UPLOAD_ACCESS_KEY_ID (or AWS_ACCESS_KEY_ID)
  R2_UPLOAD_SECRET_ACCESS_KEY (or AWS_SECRET_ACCESS_KEY)
EOF
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [ "$run_build" -eq 1 ]; then
  log "Running mise run build"
  "$project_root/lib/build.sh"
fi

[ -d "$archive_dir" ] || die "archive/ not found. Merge an export first."

bucket="${R2_BUCKET:-railsperf-exports}"
object_key="${R2_OBJECT_KEY:-railsperf-export-latest.zip}"

artifact_path=""
if command -v zip >/dev/null 2>&1; then
  artifact_path="$zip_path"
  log "Creating ZIP from archive/"
  (
    cd "$archive_dir"
    zip -rq "$artifact_path" .
  )
else
  artifact_path="$tar_path"
  log "zip not found; creating TAR from archive/"
  (
    cd "$archive_dir"
    tar -cf "$artifact_path" .
  )

  if [ -z "${R2_OBJECT_KEY:-}" ]; then
    object_key="railsperf-export-latest.tar"
  fi
fi

if [ -n "${R2_PRESIGNED_PUT_URL:-}" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required when using R2_PRESIGNED_PUT_URL"

  log "Uploading with presigned URL"
  curl --fail --silent --show-error -T "$artifact_path" "$R2_PRESIGNED_PUT_URL"
  log "Upload complete"
  exit 0
fi

command -v aws >/dev/null 2>&1 || die "aws CLI is required for direct R2 upload"

r2_account_id="${R2_ACCOUNT_ID:-${CLOUDFLARE_ACCOUNT_ID:-}}"
upload_access_key="${R2_UPLOAD_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
upload_secret_key="${R2_UPLOAD_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
upload_session_token="${R2_UPLOAD_SESSION_TOKEN:-${AWS_SESSION_TOKEN:-}}"
aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-auto}}"

[ -n "$r2_account_id" ] || die "Missing R2_ACCOUNT_ID (or CLOUDFLARE_ACCOUNT_ID)"
[ -n "$upload_access_key" ] || die "Missing R2_UPLOAD_ACCESS_KEY_ID (or AWS_ACCESS_KEY_ID)"
[ -n "$upload_secret_key" ] || die "Missing R2_UPLOAD_SECRET_ACCESS_KEY (or AWS_SECRET_ACCESS_KEY)"

log "Uploading to r2://$bucket/$object_key"
AWS_ACCESS_KEY_ID="$upload_access_key" \
AWS_SECRET_ACCESS_KEY="$upload_secret_key" \
AWS_SESSION_TOKEN="$upload_session_token" \
AWS_REGION="$aws_region" \
AWS_DEFAULT_REGION="$aws_region" \
AWS_EC2_METADATA_DISABLED=true \
aws s3 cp "$artifact_path" "s3://$bucket/$object_key" \
  --endpoint-url "https://${r2_account_id}.r2.cloudflarestorage.com"

log "Upload complete"
