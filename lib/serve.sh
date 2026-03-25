#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
build_script="$project_root/lib/build.sh"
dist_dir="$project_root/dist"
output_index="$dist_dir/index.html"
markdown_index="$dist_dir/archive.md"
qmd_dir="$dist_dir/qmd"

open_browser=1
for arg in "$@"; do
  case "$arg" in
    --no-open)
      open_browser=0
      ;;
    -h|--help)
      cat <<'EOF'
Usage: mise run serve -- [--no-open]

If dist/index.html, dist/archive.md, or dist/qmd/ are missing, runs mise run build.
Then opens dist/index.html when possible.
EOF
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

if [ ! -x "$build_script" ]; then
  printf 'Error: missing executable: lib/build.sh\n' >&2
  exit 1
fi

if [ ! -f "$output_index" ] || [ ! -s "$markdown_index" ] || [ ! -d "$qmd_dir" ]; then
  "$build_script"
else
  printf 'dist outputs already exist; skipping build\n'
fi

if [ ! -f "$output_index" ]; then
  printf 'Error: missing build output: %s\n' "$output_index" >&2
  exit 1
fi

printf 'Static viewer: file://%s\n' "$output_index"

if [ "$open_browser" -eq 0 ]; then
  exit 0
fi

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$output_index" >/dev/null 2>&1 &
elif command -v open >/dev/null 2>&1; then
  open "$output_index"
fi
