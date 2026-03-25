#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
archive_dir="$project_root/archive"
dist_dir="$project_root/dist"
site_index="$dist_dir/index.html"
single_html_export="$dist_dir/archive-single.html"
markdown_export="$dist_dir/archive.md"
markdown_export_tmp="$dist_dir/.archive.md.tmp"
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
  if [ -f "$markdown_export_tmp" ]; then
    rm -f "$markdown_export_tmp"
  fi
}
trap cleanup EXIT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage: mise run build

Builds outputs into dist/:
- static viewer site (index.html + assets)
- single-file HTML export (archive-single.html)
- Markdown export (archive.md)
EOF
  exit 0
fi

[ -d "$archive_dir" ] || die "archive/ does not exist yet. Run: mise run merge -- <export.zip>"
[ -d "$viewer_submodule" ] || die "Missing submodule: vendor/slack-export-viewer (run: git submodule update --init --recursive)"

mkdir -p "$dist_dir"
touch "$dist_dir/.gitkeep"

viewer_cmd=""
viewer_cli_cmd=""

if [ -x "$local_viewer" ]; then
  viewer_cmd="$local_viewer"
elif command -v slack-export-viewer >/dev/null 2>&1; then
  viewer_cmd="$(command -v slack-export-viewer)"
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
fi

[ -x "$viewer_cmd" ] || die "slack-export-viewer not found"
[ -x "$viewer_cli_cmd" ] || die "slack-export-viewer-cli not found"

pandoc_mode="missing"
pandoc_cmd=""
if command -v pandoc >/dev/null 2>&1; then
  pandoc_mode="path"
  pandoc_cmd="$(command -v pandoc)"
elif command -v mise >/dev/null 2>&1 && (cd "$project_root" && mise where pandoc >/dev/null 2>&1); then
  pandoc_mode="mise"
else
  die "pandoc is required to generate dist/archive.md (run: mise run setup)"
fi

log "Building static viewer site"
log "Output: $dist_dir"
"$viewer_cmd" -z "$archive_dir" --html-only -o "$dist_dir" --no-browser
[ -f "$site_index" ] || die "Build failed: $site_index not found"

log "Generating single-file export"
tmp_export_dir="${TMPDIR:-/tmp}/slack-export-viewer-export.$$"
rm -rf "$tmp_export_dir"
mkdir -p "$tmp_export_dir"
(
  cd "$tmp_export_dir"
  "$viewer_cli_cmd" export "$archive_dir" >/dev/null
)

generated_html="$(find "$tmp_export_dir" -maxdepth 1 -type f -name '*.html' | head -n 1)"
[ -n "$generated_html" ] || die "Could not locate single-file HTML export"
cp "$generated_html" "$single_html_export"

log "Converting single-file export to Markdown"
if [ "$pandoc_mode" = "path" ]; then
  "$pandoc_cmd" "$single_html_export" --from=html --to=gfm --output="$markdown_export_tmp"
else
  (
    cd "$project_root"
    mise exec -- pandoc "$single_html_export" --from=html --to=gfm --output="$markdown_export_tmp"
  )
fi

[ -s "$markdown_export_tmp" ] || die "Markdown export failed: empty output"
mv "$markdown_export_tmp" "$markdown_export"
touch "$dist_dir/.gitkeep"

log "Build complete"
log "Site: $site_index"
log "Markdown: $markdown_export"
