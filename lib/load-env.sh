#!/usr/bin/env bash

load_env_file() {
  local env_file="$1"
  local restore_nounset=0

  if [ ! -f "$env_file" ]; then
    return 0
  fi

  case $- in
    *u*) restore_nounset=1 ;;
  esac

  set +u
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  if [ "$restore_nounset" -eq 1 ]; then
    set -u
  fi
}
