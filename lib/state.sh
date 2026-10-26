#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
archive_dir="$project_root/archive"
tarball=""

# shellcheck disable=SC1091
source "$project_root/lib/load-env.sh"
# shellcheck disable=SC1091
source "$project_root/lib/r2.sh"
load_env_file "$project_root/.env"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tarball" ] && [ -f "$tarball" ]; then
    rm -f "$tarball"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: mise run state -- pull|push

Syncs archive/ with a private tarball in R2.
  pull   download and extract into archive/ (refuses if archive/ exists)
  push   upload archive/ as the new tarball

Env vars:
  R2_BUCKET (default: railsperf-exports)
  R2_STATE_KEY (default: state/archive.tar.gz)
  plus the R2 credentials used by mise run upload
EOF
}

[ "$#" -eq 1 ] || { usage >&2; exit 1; }

bucket="${R2_BUCKET:-railsperf-exports}"
state_key="${R2_STATE_KEY:-state/archive.tar.gz}"
state_uri="s3://$bucket/$state_key"
tarball="${TMPDIR:-/tmp}/slack-archive-state.$$.tar.gz"

case "$1" in
  pull)
    [ ! -e "$archive_dir" ] || die "archive/ already exists; move it aside before pulling"
    log "Downloading $state_uri"
    r2_aws s3 cp "$state_uri" "$tarball"
    tar -xzf "$tarball" -C "$project_root"
    [ -d "$archive_dir" ] || die "State tarball did not contain archive/"
    log "Restored archive/"
    ;;
  push)
    [ -d "$archive_dir" ] || die "archive/ not found"
    COPYFILE_DISABLE=1 tar -czf "$tarball" -C "$project_root" archive
    log "Uploading archive/ to $state_uri"
    r2_aws s3 cp "$tarball" "$state_uri"
    log "State upload complete"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
