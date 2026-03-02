# Slack Export Archive

Local tooling to maintain a merged Slack export archive and browse it with `slack-export-viewer`.

## What this repo contains

- `archive/` — merged, living export directory (JSON files by channel/day)
- `imports/` — raw export ZIPs copied in for reference
- `bin/merge` — Ruby merge script (ZIP or directory input)
- `bin/serve` — fish script to launch local viewer
- `bin/upload` — fish script to zip + upload archive to Cloudflare R2
- `Gemfile` — ruby dependencies (`rubyzip`)
- `PLAN.md` — implementation plan and phase-2 notes

## Included exports

Copied from `~/Documents/Inbox`:

- `imports/full-export-2016-03-05_to_2026-03-01.zip`
- `imports/monthly-example-2026-01.zip`

## Requirements

- Ruby (with `bundle`)
- Python 3 (used by `bin/serve` to bootstrap a local venv)
- fish shell (for `bin/serve`, `bin/upload`)
- `gum` (for script UI)
- `aws` CLI (only for `bin/upload`)

## Viewer source of truth

`slack-export-viewer` is vendored as a git submodule:

- path: `vendor/slack-export-viewer`
- remote: `https://github.com/speedshop/slack-export-viewer`

Initialize/update it with:

```bash
git submodule update --init --recursive
```

Install ruby deps:

```bash
bundle install
```

## Merge workflow

Merge a new Slack export (ZIP or extracted dir) into `archive/`:

```bash
ruby bin/merge /path/to/export.zip
```

Optional custom archive target:

```bash
ruby bin/merge /path/to/export.zip /path/to/archive
```

### Merge behavior

- `users.json` merged by `id` (incoming record wins)
- `channels.json` merged by `id` (incoming record wins)
- Channel daily files (`YYYY-MM-DD.json`) merged by message `ts`
- `#random` and `#introductions` are excluded from archive/build/export output
- Duplicate `ts` values are replaced by incoming message
- Output sorted by timestamp
- Idempotent: rerunning same export does not grow duplicates

## Build and open local viewer (static files)

```fish
bin/serve
```

`bin/serve` now:

1. bootstraps a local venv at `.venv-sev/` (first run only)
2. installs the submodule version of `slack-export-viewer`
3. builds a static site to `viewer-site/`
4. opens `viewer-site/index.html` via `file://`

This avoids running a live local Flask server.

Message order:

- default: newest → oldest

## Upload latest archive to R2

```fish
bin/upload
```

This script:

1. zips `archive/` to `railsperf-export-latest.zip`
2. uploads to `s3://$R2_BUCKET/$R2_OBJECT_KEY`

Environment variables:

- required: `R2_ACCOUNT_ID`
- optional: `R2_BUCKET` (default `railsperf-exports`)
- optional: `R2_OBJECT_KEY` (default `railsperf-export-latest.zip`)

AWS credentials must already be configured with an R2-compatible token.

## Future public export packaging (notes)

When shipping exports to end users, prefer:

1. static HTML output (single file or multi-file bundle) users can open directly
2. a short README that explains navigation and search options
3. optional local search guidance using `qmd` (https://github.com/tobi/qmd)

## Current state (as of implementation)

- `archive/` built and merged from included exports
- verified repeated merges are idempotent
- `#random` and `#introductions` are excluded from merge/build output
- local viewer is static (`file://.../viewer-site/index.html`)
