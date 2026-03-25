#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
dist_dir="$project_root/dist"
legacy_output_dir="$project_root/viewer-site"
viewer_venv="$project_root/.venv-sev"

remove_venv=0
for arg in "$@"; do
  case "$arg" in
    --all)
      remove_venv=1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: mise run clean -- [--all]

Removes generated artifacts from dist/ (keeps dist/.gitkeep).
Use --all to also remove .venv-sev/.
EOF
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

removed_any=0

if [ -d "$dist_dir" ]; then
  if [ -n "$(find "$dist_dir" -mindepth 1 ! -name '.gitkeep' -print -quit)" ]; then
    printf 'Cleaning dist/\n'
    find "$dist_dir" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} +
    removed_any=1
  fi
fi

if [ -e "$legacy_output_dir" ]; then
  printf 'Removing legacy viewer-site/\n'
  rm -rf "$legacy_output_dir"
  removed_any=1
fi

if [ "$remove_venv" -eq 1 ]; then
  if [ -e "$viewer_venv" ]; then
    printf 'Removing .venv-sev/\n'
    rm -rf "$viewer_venv"
    removed_any=1
  fi
elif [ -e "$viewer_venv" ]; then
  printf 'Keeping .venv-sev/ (use mise run clean -- --all to remove it)\n'
fi

mkdir -p "$dist_dir"
touch "$dist_dir/.gitkeep"

if [ "$removed_any" -eq 0 ]; then
  printf 'Nothing to clean\n'
else
  printf 'Clean complete\n'
fi
