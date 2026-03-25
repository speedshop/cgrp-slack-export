# Terraform: Cloudflare R2 bucket

This directory manages the R2 bucket described in `PLAN.md`.

## Inputs

Set these in `.env` (see `.env.example`):

- `TF_VAR_cloudflare_account_id`
- `TF_VAR_cloudflare_api_token`
- `TF_VAR_r2_bucket_name` (default: `railsperf-exports`)
- `TF_VAR_r2_object_key` (default: `railsperf-export-latest.zip`)

## Apply

Run from repo root:

```bash
mise run tf -- init
mise run tf -- plan
mise run tf -- apply
```

After apply, go create the R2 API tokens in Cloudflare dashboard:

1. upload token (`Object Read & Write`) for `mise run upload`
2. presign token (`Object Read`) for the bot
