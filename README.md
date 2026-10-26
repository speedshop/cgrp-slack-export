# Slack Export Archive

Local tooling to maintain a merged Slack export archive, build browsable outputs, and publish the latest export ZIP to Cloudflare R2.

## Repo layout

- `archive/` — merged Slack export data (living archive)
- `imports/` — raw export ZIPs
- `dist/` — generated viewer + markdown outputs for qmd-style indexing
- `lib/` — task implementations called by `mise`
- `mise.toml` — tool versions + task entrypoints

## 1) Setup tools

```bash
mise run setup
```

`mise run setup` checks/installs tools from `mise.toml` (Python, AWS CLI), initializes submodules, and checks dependencies.

## 2) Configure secrets with `.env`

```bash
cp .env.example .env
```

Fill in real values for:

- R2 account + upload endpoint settings
- R2 upload keypair (Read & Write token)
- bucket/object names (defaults already set)

`mise run upload` automatically loads `.env`.

## 3) Monthly workflow

### Automated (GitHub Actions)

`.github/workflows/monthly-publish.yml` runs at 09:00 UTC on the 1st of every month (and on demand via "Run workflow"):

1. `mise run state -- pull` restores `archive/` from `s3://railsperf-exports/state/archive.tar.gz`
2. `mise run fetch -- <dir>` pulls the previous month of public channel history from the Slack Web API
3. `mise run merge`, `mise run build`, and `mise run upload` publish `railsperf-export-latest.zip`
4. `mise run state -- push` saves the updated `archive/` back to R2

Each secret is scoped to the steps that need it. Tools are installed from `mise.lock` with checksums, and the viewer's Python dependencies from the hash-locked `lib/requirements.lock`. Viewer log records and exception messages are suppressed so message content never reaches the public Actions log, and `mise run upload` refuses to ship a `dist/` containing Slack `xoxe-` file tokens.

Required repository secrets: `SLACK_TOKEN`, `R2_ACCOUNT_ID`, `R2_UPLOAD_ACCESS_KEY_ID`, `R2_UPLOAD_SECRET_ACCESS_KEY`.

`SLACK_TOKEN` is a user token (`xoxp-…`) from an internal Slack app created from this manifest and installed to the workspace:

```yaml
display_information:
  name: Slack Export Archiver
oauth_config:
  scopes:
    user:
      - channels:history
      - channels:read
      - users:read
settings:
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

Seed the state once from a machine with an up-to-date `archive/`:

```bash
mise run state -- push
```

### One-shot publish from a manual export

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

## Markdown export for qmd

`mise run build` now writes a qmd-friendly markdown corpus into:

- `dist/archive.md` — top-level index file
- `dist/markdown/<channel>/<YYYY-MM>.md` — monthly channel documents

These files are structured for local indexing tools like qmd: real headings, smaller documents, and newest-first message ordering.

## Upload behavior

`mise run upload` creates `railsperf-export-latest.zip` from `dist/` (falls back to `.tar` if `zip` is unavailable), then uploads via:

1. `R2_PRESIGNED_PUT_URL` + `curl`, or
2. AWS CLI to `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` using:
   - `R2_ACCOUNT_ID`
   - `R2_UPLOAD_ACCESS_KEY_ID`
   - `R2_UPLOAD_SECRET_ACCESS_KEY`

## Fetch behavior

- writes the same layout as a Slack export: `users.json`, `channels.json`, `<channel>/<YYYY-MM-DD>.json`
- day files are bucketed in `America/Los_Angeles`, matching Slack's exports
- includes thread replies posted in the window to threads started up to 90 days earlier, and refreshes those parents' `replies` lists
- `--since YYYY-MM-DD` overrides the default start (first day of the previous month)

## Merge behavior

- `users.json` merged by `id` (incoming wins)
- `channels.json` merged by `id` (incoming wins)
- per-day channel files merged by message `ts`
- excluded channels: `#random`, `#introductions`
- idempotent when re-merging same export

