# Slack Export Archive

Local tooling to maintain a merged Slack export archive, build browsable outputs, and publish the latest export ZIP to Cloudflare R2.

## Repo layout

- `archive/` — merged Slack export data (living archive)
- `imports/` — raw export ZIPs
- `dist/` — generated viewer + markdown outputs
- `lib/` — task implementations called by `mise`
- `mise.toml` — tool versions + task entrypoints
- `terraform/` — Cloudflare R2 bucket IaC

## 1) Setup tools

```bash
mise run setup
```

`mise run setup` checks/installs tools from `mise.toml` (Python, AWS CLI, Pandoc, Terraform), initializes submodules, and checks dependencies.

## 2) Configure secrets with `.env`

```bash
cp .env.example .env
```

Fill in real values for:

- Cloudflare account + API token (Terraform)
- R2 upload keypair (Read & Write token)
- bucket/object names (defaults already set)

`mise run upload` and `mise run tf` automatically load `.env`.

## 3) Create/manage the R2 bucket with Terraform

```bash
mise run tf -- init
mise run tf -- plan
mise run tf -- apply
```

`mise run tf` auto-loads `.env` and runs Terraform in `terraform/`.
This manages the `railsperf-exports` R2 bucket (or your configured name).

## 4) Monthly workflow

### One-shot publish (recommended)

```bash
mise run publish -- imports/monthly-2026-05.zip
```

Use `mise run publish -- --skip-merge` when `archive/` is already up to date and you only want build + upload.

### Or run steps manually

```bash
mise run merge -- imports/monthly-2026-05.zip
mise run build
mise run upload
```

## Upload behavior

`mise run upload` creates `railsperf-export-latest.zip` from `archive/` (falls back to `.tar` if `zip` is unavailable), then uploads via:

1. `R2_PRESIGNED_PUT_URL` + `curl`, or
2. AWS CLI to `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` using:
   - `R2_ACCOUNT_ID` (or `CLOUDFLARE_ACCOUNT_ID`)
   - `R2_UPLOAD_ACCESS_KEY_ID`
   - `R2_UPLOAD_SECRET_ACCESS_KEY`

## Merge behavior

- `users.json` merged by `id` (incoming wins)
- `channels.json` merged by `id` (incoming wins)
- per-day channel files merged by message `ts`
- excluded channels: `#random`, `#introductions`
- idempotent when re-merging same export

## Compatibility shims

The old `bin/*` commands still exist as tiny wrappers around the corresponding `mise` tasks.
