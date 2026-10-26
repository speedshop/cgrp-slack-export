#!/usr/bin/env bash

r2_aws() {
  command -v aws >/dev/null 2>&1 || die "aws CLI is required for direct R2 access"

  local r2_account_id="${R2_ACCOUNT_ID:-${CLOUDFLARE_ACCOUNT_ID:-}}"
  local access_key="${R2_UPLOAD_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
  local secret_key="${R2_UPLOAD_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
  local session_token="${R2_UPLOAD_SESSION_TOKEN:-${AWS_SESSION_TOKEN:-}}"
  local aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-auto}}"

  [ -n "$r2_account_id" ] || die "Missing R2_ACCOUNT_ID (or CLOUDFLARE_ACCOUNT_ID)"
  [ -n "$access_key" ] || die "Missing R2_UPLOAD_ACCESS_KEY_ID (or AWS_ACCESS_KEY_ID)"
  [ -n "$secret_key" ] || die "Missing R2_UPLOAD_SECRET_ACCESS_KEY (or AWS_SECRET_ACCESS_KEY)"

  AWS_ACCESS_KEY_ID="$access_key" \
  AWS_SECRET_ACCESS_KEY="$secret_key" \
  AWS_SESSION_TOKEN="$session_token" \
  AWS_REGION="$aws_region" \
  AWS_DEFAULT_REGION="$aws_region" \
  AWS_EC2_METADATA_DISABLED=true \
  aws "$@" --endpoint-url "https://${r2_account_id}.r2.cloudflarestorage.com"
}
