#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
archive_dir="$project_root/archive"
dist_dir="$project_root/dist"
site_index="$dist_dir/index.html"
single_html_export="$dist_dir/archive-single.html"
markdown_index="$dist_dir/archive.md"
qmd_dir="$dist_dir/qmd"
readme_dist_source="$project_root/README-DIST.md"
readme_dist_target="$dist_dir/README.md"
viewer_venv="$project_root/.venv-sev"
viewer_submodule="$project_root/vendor/slack-export-viewer"
local_viewer="$viewer_venv/bin/slack-export-viewer"
local_viewer_cli="$viewer_venv/bin/slack-export-viewer-cli"
tmp_export_dir=""

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

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage: mise run build

Builds outputs into dist/:
- static viewer site (index.html + assets)
- single-file HTML export (archive-single.html)
- qmd-oriented Markdown corpus (archive.md + qmd/**/*.md)
- distribution readme (README.md, copied from README-DIST.md)
EOF
  exit 0
fi

[ -d "$archive_dir" ] || die "archive/ does not exist yet. Run: mise run merge -- <export.zip>"
[ -d "$viewer_submodule" ] || die "Missing submodule: vendor/slack-export-viewer (run: git submodule update --init --recursive)"
[ -f "$readme_dist_source" ] || die "Missing distribution readme: $readme_dist_source"

mkdir -p "$dist_dir"
touch "$dist_dir/.gitkeep"

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
rm -rf "$qmd_dir"
"$viewer_python" "$project_root/lib/export_qmd.py" "$archive_dir" "$dist_dir"

[ -s "$markdown_index" ] || die "Markdown index export failed: $markdown_index"
[ -d "$qmd_dir" ] || die "qmd export directory missing: $qmd_dir"

log "Copying distribution readme"
cp "$readme_dist_source" "$readme_dist_target"
[ -s "$readme_dist_target" ] || die "Distribution readme copy failed: $readme_dist_target"

touch "$dist_dir/.gitkeep"

log "Build complete"
log "Site: $site_index"
log "Markdown index: $markdown_index"
log "qmd corpus: $qmd_dir"
