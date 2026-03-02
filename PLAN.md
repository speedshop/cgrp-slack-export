# Plan: Slack Export Archive + Local Viewer

## Context

railsperf.slack.com is currently on Slack Pro. The goal is to:
1. Do a full export (all history, public channels) while still on Pro
2. Set up slack-export-viewer locally to browse it
3. Build a merge script so future monthly exports from the Free plan can be incrementally added

## Prerequisites (user action)

1. Go to railsperf.slack.com admin: **Settings & Administration > Workspace Settings > Import/Export Data > Export**
2. Select **"Entire history"** and start the export
3. Download the resulting ZIP file to `~/Downloads/` (or anywhere)

## What I'll build

### Directory structure
```
archive/              # The living, merged export directory
bin/
  merge               # Ruby script: merge a new export ZIP into archive/
  serve               # Fish script: launch slack-export-viewer
Gemfile               # rubyzip dependency
```

### 1. `bin/merge` (Ruby)
- Takes a path to a Slack export ZIP (or unzipped directory)
- Extracts to temp dir if ZIP, detects nested root dir
- Merges `users.json` and `channels.json` by `id` field (import wins for updates)
- Merges each channel's daily message files (`YYYY-MM-DD.json`) by `ts` field (import wins, deduplicates)
- Sorts messages by timestamp after merge
- Idempotent: running twice with the same export produces the same result
- Prints progress per channel

### 2. `bin/serve` (Fish)
- Launches `slack-export-viewer -z archive/ -p 5000`
- Already installed at `/Users/nateberkopec/.local/bin/slack-export-viewer`

### 3. `Gemfile`
- Just `rubyzip` (already installed: 3.2.2)

## Future monthly workflow
```
# Download latest export from Slack (free plan, 90-day window)
ruby bin/merge ~/Downloads/new-slack-export.zip
bin/serve
```

The 90-day window means ~60 days overlap with the prior month. The merge script handles this via ts-based deduplication.

## Verification
1. `ruby bin/merge path/to/full-export.zip` - should populate `archive/` with all channels
2. `bin/serve` - should open viewer at localhost:5000 with all history
3. Run merge again with same ZIP - archive should be unchanged (idempotent)

---

## Phase 2: Public Distribution via Signed URLs

### Overview

Users DM `@speedy` in Slack to request the export. The bot generates a
presigned R2 URL (7-day TTL) pointing at the merged export ZIP and replies
with it. Only current workspace members can reach the bot.

### Architecture

```
Slack user  ──DM──>  @speedy bot
                        │
                        ├─ 1. User is in workspace (implicit: they can DM the bot)
                        ├─ 2. Generate presigned GET URL for R2 object (7-day expiry)
                        └─ 3. Reply with the URL

You (monthly) ──>  bin/merge + bin/upload ──>  Cloudflare R2 bucket
```

### Infrastructure

**Cloudflare R2 bucket** (S3-compatible object storage, zero egress fees)
- Bucket name: e.g. `railsperf-exports`
- Object key: `railsperf-export-latest.zip` (overwritten each month)
- Public access: **disabled**. All access is via presigned URLs only.
- No Worker, no CDN, no domain needed. Presigned URLs hit the R2 endpoint directly.

**R2 API token** (created in Cloudflare dashboard > R2 > Manage R2 API Tokens)
- Two sets of credentials needed:
  1. **Upload token** (for your local `bin/upload` script): permissions `Object Read & Write`
  2. **Presign token** (for the bot): permissions `Object Read` only
- Each token gives you an Access Key ID + Secret Access Key (S3-style)

### Bot behavior (what @speedy does)

When a user sends a DM (or a specific command like "export" or "archive"):

1. **Generate a presigned GET URL** using the R2 presign credentials:
   - S3 endpoint: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
   - Bucket: `railsperf-exports`
   - Key: `railsperf-export-latest.zip`
   - Expiry: 7 days (604800 seconds)
2. **Reply** with the URL in an ephemeral or DM message

**API the bot calls** (S3-compatible presigned URL generation):
- No HTTP request to R2 is needed at signing time. Presigned URLs are computed
  locally using HMAC-SHA256 over the credentials + expiry + object path. Any
  S3 SDK does this in-memory.
- Library examples:
  - **Ruby**: `Aws::S3::Presigner` from `aws-sdk-s3` gem
  - **Node**: `@aws-sdk/s3-request-presigner` + `GetObjectCommand`
  - **Python**: `boto3` `generate_presigned_url`
- The SDK needs: endpoint URL, access key ID, secret access key, region (`auto` for R2)

**Slack APIs the bot uses** (already set up, listing for completeness):
- Receives: `message.im` event (or `app_mention` if in channels)
- Sends: `chat.postMessage` to the DM conversation with the presigned URL

### Upload workflow (`bin/upload`)

Run after `bin/merge` when you want to publish a new version:

```fish
# 1. ZIP the archive
cd archive && zip -r ../railsperf-export-latest.zip . && cd ..

# 2. Upload to R2 (using rclone, aws cli, or a script)
# With aws cli:
aws s3 cp railsperf-export-latest.zip \
  s3://railsperf-exports/railsperf-export-latest.zip \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com

# Or with rclone (after configuring an "r2" remote):
rclone copyto railsperf-export-latest.zip r2:railsperf-exports/railsperf-export-latest.zip
```

### Full monthly workflow (future)

```fish
# 1. Download new export from Slack (free plan)
# 2. Merge into archive
ruby bin/merge ~/Downloads/new-slack-export.zip
# 3. ZIP and upload
bin/upload
# 4. Done. Users can request fresh URL from @speedy.
```

### Access control summary

| Layer | Mechanism |
|-------|-----------|
| Who can request | Only railsperf.slack.com members (they must be in the workspace to DM @speedy) |
| URL lifetime | 7 days, then the signature expires and R2 returns 403 |
| Bucket access | No public access. Presigned URLs are the only way in. |
| Upload access | Separate write-capable token, held only by you |
| Link sharing risk | A user could share their URL with a non-member. Acceptable tradeoff for simplicity — the URL expires in 7 days and the content is public channel history only. |

### Cloudflare setup checklist

1. Create R2 bucket `railsperf-exports` in Cloudflare dashboard
2. Create R2 API token for uploads (Read & Write)
3. Create R2 API token for the bot (Read only)
4. Configure `aws` CLI or `rclone` locally with the upload token
5. Give the bot the read-only credentials (env vars or secrets manager)
6. Test: upload a file, generate a presigned URL, download it
