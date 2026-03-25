# Slack Export Bundle

This directory contains a browser-friendly HTML export and a markdown corpus for text search and local indexing.

## 1. How to view the HTML export

Use the HTML files when you want to browse the archive like a website.

- Open `./index.html` in a web browser to use the full viewer.
- Open `./archive-single.html` if you want the whole export in one HTML file.
- Channel pages and static assets live alongside `index.html`, so keep the directory structure intact.

Examples:

```bash
open ./index.html
# or
xdg-open ./index.html
```

If one file looks easier to share or inspect, use `./archive-single.html`. For normal browsing, `./index.html` is the better starting point.

## 2. How to search the export in general with CLI tools or agents

For text search, start with the markdown export, not the HTML.

- `./archive.md` is the top-level index.
- `./qmd/` contains the searchable corpus.
- Files are split by channel and month: `./qmd/<channel>/<YYYY-MM>.md`.

Useful CLI examples:

```bash
rg "incident review" ./qmd
rg -n "postgres|redis" ./qmd
rg -l "feature flag" ./qmd
```

If you need a broad file listing first:

```bash
find ./qmd -type f | sort
```

You can also point a coding agent or local assistant at this directory and ask it to search or summarize the export. In practice, the best root is `./qmd/`, with `./archive.md` as the map of what is available.

Use the HTML files when you need to read a thread in a browser. Use the markdown files when you want fast grep-style search, indexing, chunking, or agent workflows.

## 3. How to use QMD with this export

This export is already shaped for QMD.

- Use `./qmd/` as the collection root.
- Use `./archive.md` as the human-readable index into the collection.
- Do not point QMD at the HTML files unless you specifically want raw HTML indexing.

The markdown corpus is organized to work well with local indexing tools:

- one file per channel per month
- real markdown headings
- newest-first message ordering
- smaller documents instead of one giant file

A simple workflow is:

1. Index `./qmd/` in QMD.
2. Open `./archive.md` to see which channel/month files exist.
3. Search in QMD, then jump to the matching markdown file for context.
4. If needed, open `./index.html` to browse the same material in the viewer.
