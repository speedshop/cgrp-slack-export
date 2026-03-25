#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
archive_dir="$project_root/archive"
dist_dir="$project_root/dist"
site_index="$dist_dir/index.html"
single_html_export="$dist_dir/archive-single.html"
markdown_index="$dist_dir/archive.md"
markdown_dir="$dist_dir/markdown"
legacy_qmd_dir="$dist_dir/qmd"
readme_dist_source="$project_root/README-DIST.md"
readme_dist_target="$dist_dir/README.md"
license_dist_source="$project_root/LICENSE-DIST"
license_target="$dist_dir/LICENSE"
viewer_venv="$project_root/.venv-sev"
viewer_submodule="$project_root/vendor/slack-export-viewer"
local_viewer="$viewer_venv/bin/slack-export-viewer"
local_viewer_cli="$viewer_venv/bin/slack-export-viewer-cli"
tmp_export_dir=""
force_build=0

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp_export_dir" ] && [ -d "$tmp_export_dir" ]; then
    rm -rf "$tmp_export_dir"
  fi
}
trap cleanup EXIT

build_is_current() {
  [ -f "$site_index" ] || return 1
  [ -f "$single_html_export" ] || return 1
  [ -s "$markdown_index" ] || return 1
  [ -d "$markdown_dir" ] || return 1
  [ -s "$readme_dist_target" ] || return 1
  [ -s "$license_target" ] || return 1

  newer_input="$(find \
    "$archive_dir" \
    "$readme_dist_source" \
    "$license_dist_source" \
    "$project_root/lib/build.sh" \
    "$project_root/lib/export_qmd.py" \
    "$project_root/lib/strip_export_html.py" \
    "$project_root/lib/slack_export_viewer_desc.py" \
    "$project_root/vendor/slack-export-viewer" \
    -type f -newer "$readme_dist_target" -print -quit 2>/dev/null)"
  [ -z "$newer_input" ]
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force_build=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: mise run build [-- --force]

Builds outputs into dist/:
- static viewer site (index.html + assets)
- single-file HTML export (archive-single.html)
- qmd-oriented Markdown corpus (archive.md + markdown/**/*.md)
- distribution readme (README.md, copied from README-DIST.md)
- license file (LICENSE)

Skips work when dist/ is already current unless --force is passed.
EOF
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -d "$archive_dir" ] || die "archive/ does not exist yet. Run: mise run merge -- <export.zip>"
[ -d "$viewer_submodule" ] || die "Missing submodule: vendor/slack-export-viewer (run: git submodule update --init --recursive)"
[ -f "$readme_dist_source" ] || die "Missing distribution readme: $readme_dist_source"
[ -f "$license_dist_source" ] || die "Missing distribution license: $license_dist_source"

mkdir -p "$dist_dir"
touch "$dist_dir/.gitkeep"

if [ "$force_build" -eq 0 ] && build_is_current; then
  log "dist outputs are current; skipping build"
  exit 0
fi

viewer_cmd=""
viewer_cli_cmd=""
viewer_python=""
viewer_wrapper="$project_root/lib/slack_export_viewer_desc.py"

if [ -x "$local_viewer" ]; then
  viewer_cmd="$local_viewer"
  viewer_python="$viewer_venv/bin/python"
elif command -v slack-export-viewer >/dev/null 2>&1; then
  viewer_cmd="$(command -v slack-export-viewer)"
  IFS= read -r viewer_python_shebang < "$viewer_cmd"
  viewer_python="${viewer_python_shebang#\#!}"
fi

if [ -x "$local_viewer_cli" ]; then
  viewer_cli_cmd="$local_viewer_cli"
elif command -v slack-export-viewer-cli >/dev/null 2>&1; then
  viewer_cli_cmd="$(command -v slack-export-viewer-cli)"
fi

if [ -z "$viewer_cmd" ] || [ -z "$viewer_cli_cmd" ]; then
  command -v python3 >/dev/null 2>&1 || die "python3 is required to bootstrap local viewer"

  log "Bootstrapping local slack-export-viewer virtualenv"
  python3 -m venv "$viewer_venv"
  "$viewer_venv/bin/python" -m pip install --upgrade pip >/dev/null
  "$viewer_venv/bin/python" -m pip install -e "$viewer_submodule"

  viewer_cmd="$local_viewer"
  viewer_cli_cmd="$local_viewer_cli"
  viewer_python="$viewer_venv/bin/python"
fi

[ -x "$viewer_cmd" ] || die "slack-export-viewer not found"
[ -x "$viewer_cli_cmd" ] || die "slack-export-viewer-cli not found"
[ -x "$viewer_python" ] || die "Could not determine slack-export-viewer python interpreter"
[ -f "$viewer_wrapper" ] || die "Missing viewer wrapper: $viewer_wrapper"

log "Building static viewer site"
log "Output: $dist_dir"
"$viewer_python" "$viewer_wrapper" viewer -z "$archive_dir" --html-only -o "$dist_dir" --no-browser
[ -f "$site_index" ] || die "Build failed: $site_index not found"

log "Generating single-file export"
tmp_export_dir="${TMPDIR:-/tmp}/slack-export-viewer-export.$$"
rm -rf "$tmp_export_dir"
mkdir -p "$tmp_export_dir"
(
  cd "$tmp_export_dir"
  "$viewer_python" "$viewer_wrapper" export "$archive_dir" >/dev/null
)

generated_html="$(find "$tmp_export_dir" -maxdepth 1 -type f -name '*.html' | head -n 1)"
[ -n "$generated_html" ] || die "Could not locate single-file HTML export"
cp "$generated_html" "$single_html_export"

log "Slimming generated HTML"
"$viewer_python" "$project_root/lib/strip_export_html.py" "$dist_dir"

log "Generating qmd-oriented Markdown corpus"
rm -f "$markdown_index"
rm -rf "$markdown_dir"
rm -rf "$legacy_qmd_dir"
"$viewer_python" "$project_root/lib/export_qmd.py" "$archive_dir" "$dist_dir"

[ -s "$markdown_index" ] || die "Markdown index export failed: $markdown_index"
[ -d "$markdown_dir" ] || die "markdown export directory missing: $markdown_dir"

log "Copying distribution readme"
generated_on="$(date +%F)"
archive_date_range="$($viewer_python - "$archive_dir" <<'PY'
from pathlib import Path
import re
import sys

archive_dir = Path(sys.argv[1])
date_re = re.compile(r"^\d{4}-\d{2}-\d{2}\.json$")
dates = sorted(
    path.stem
    for path in archive_dir.glob("*/*.json")
    if date_re.match(path.name)
)

if not dates:
    raise SystemExit(1)

print(f"{dates[0]} {dates[-1]}")
PY
)" || die "Could not determine archive date range from $archive_dir"
IFS=' ' read -r archive_start_date archive_end_date <<EOF
$archive_date_range
EOF
{
  printf 'This export was generated on %s and contains Slack history from %s to %s.\n\n' \
    "$generated_on" "$archive_start_date" "$archive_end_date"
  cat "$readme_dist_source"
} > "$readme_dist_target"
[ -s "$readme_dist_target" ] || die "Distribution readme copy failed: $readme_dist_target"

log "Copying distribution license"
cp "$license_dist_source" "$license_target"
[ -s "$license_target" ] || die "Distribution license copy failed: $license_target"

touch "$dist_dir/.gitkeep"

log "Build complete"
log "Site: $site_index"
log "Markdown index: $markdown_index"
log "markdown corpus: $markdown_dir"
