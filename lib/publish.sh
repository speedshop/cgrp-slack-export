#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
merge_script="$project_root/lib/merge.py"
build_script="$project_root/lib/build.sh"
upload_script="$project_root/lib/upload.sh"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  mise run publish -- <slack-export.zip|directory> [archive-path]
  mise run publish -- --skip-merge

Runs the full monthly pipeline:
  1) merge (unless --skip-merge)
  2) build
  3) upload
EOF
}

skip_merge=0
merge_input=""
archive_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-merge)
      skip_merge=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "$merge_input" ]; then
        merge_input="$1"
      elif [ -z "$archive_path" ]; then
        archive_path="$1"
      else
        die "Too many arguments. See --help."
      fi
      shift
      ;;
  esac
done

[ -x "$merge_script" ] || die "missing executable: $merge_script"
[ -x "$build_script" ] || die "missing executable: $build_script"
[ -x "$upload_script" ] || die "missing executable: $upload_script"

if [ "$skip_merge" -eq 0 ]; then
  [ -n "$merge_input" ] || die "Missing merge input. Provide a Slack export ZIP/directory or use --skip-merge."

  log "Step 1/3: merge"
  if [ -n "$archive_path" ]; then
    "$merge_script" "$merge_input" "$archive_path"
  else
    "$merge_script" "$merge_input"
  fi
else
  if [ -n "$merge_input" ] || [ -n "$archive_path" ]; then
    die "Do not pass merge arguments with --skip-merge."
  fi
  log "Step 1/3: merge (skipped)"
fi

log "Step 2/3: build"
"$build_script"

log "Step 3/3: upload"
"$upload_script"

log "✅ Publish complete"
