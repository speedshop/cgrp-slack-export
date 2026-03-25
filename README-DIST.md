# Slack Export Bundle

This directory contains a browser-friendly HTML export and a markdown corpus for text search and local indexing.

It is updated monthly.

## 1. How to view the HTML export

Use the HTML files when you want to browse the archive like a website. It should just work in your browser and doesn't require you to serve the files over HTML.

- Open `./index.html` in a web browser to use the full viewer.
- Open `./archive-single.html` if you want the whole export in one HTML file.

## 2. How to search the export in general with CLI tools or agents

For text search, start with the markdown export, not the HTML.

- `./archive.md` is the top-level index.
- `./markdown/` contains the searchable corpus.
- Files are split by channel and month: `./markdown/<channel>/<YYYY-MM>.md`.

```bash
rg "incident review" ./markdown
rg -n "postgres|redis" ./markdown
rg -l "feature flag" ./markdown
```

You can also point a coding agent or other LLM assistant at this directory and ask it to search or summarize the export.

## 3. How to use QMD with this export

QMD is a local markdown search engine that can do more than plain grep: keyword search, semantic search, hybrid ranked search, and document retrieval for agents.

If you only need exact text matching, `rg` is still great. Use QMD when you want any of these:

- natural-language search like “how can we automatically schedule Postgres vacuums?”
- semantically ranked results instead of raw grep matches
- a fast way to hand relevant sub-files/context to an agent
- a way to retrieve full documents after search

### Step 1: install QMD

QMD requires Node.js 22+.

```bash
npm install -g @tobilu/qmd
```

If you do not want a global install, replace `qmd` in the commands below with `npx @tobilu/qmd`.

### Step 2: open this bundle and create a dedicated QMD index

Run these commands from inside this `dist/` directory:

```bash
cd /path/to/this/dist
qmd --index slack-export collection add "$PWD/markdown" --name slack-export --mask "**/*.md"
qmd --index slack-export context add qmd://slack-export "Slack export markdown corpus split by channel and month. Use this to find decisions, incidents, migrations, and historical discussions."
qmd --index slack-export status
```

### Step 3: generate embeddings so QMD's best search modes work

```bash
qmd --index slack-export embed
```

This step enables semantic search and hybrid search. On first run, QMD will download its local models and build embeddings, so expect the first run to take longer than later runs.

### Step 4: run searches

Start with plain keyword search:

```bash
qmd --index slack-export search -c slack-export '"incident review"'
qmd --index slack-export search -c slack-export 'postgres migration'
```

Then use QMD's higher-value hybrid search:

```bash
qmd --index slack-export query -c slack-export "What performance improvements came in Rails 7?"
qmd --index slack-export query -c slack-export "What is the cost of having >500 database connections at once?"
```

If you want to be more explicit, QMD also supports structured multi-line queries:

```bash
qmd --index slack-export query -c slack-export $'intent: incidents, debugging, rollbacks, and follow-up actions\nlex: "incident review" outage rollback\nvec: how do people fix outages'
```

### Step 5: retrieve files after searching

If a result shows a docid like `#abc123`, fetch it directly:

```bash
qmd --index slack-export get "#abc123"
```

And if you want agent-friendly output, use file-mode output:

```bash
qmd --index slack-export query -c slack-export --files --all --min-score 0.35 "postgres migration"
```

### Step 6: refresh QMD after you rebuild this export

If this bundle is replaced with a newer build, refresh the QMD index:

```bash
qmd --index slack-export update
qmd --index slack-export embed
```

Use `./archive.md` as the human-readable map of the corpus, `./markdown/` as the collection root for QMD, and `./index.html` when you want to read the same material in the browser viewer.
