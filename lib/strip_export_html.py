#!/usr/bin/env python3

import re
import sys
from pathlib import Path

USER_AVATAR_IMG = re.compile(r'\s*<img[^>]*class="user_icon(?:_reply)?"[^>]*>\s*', re.IGNORECASE)
USER_AVATAR_PLACEHOLDER = re.compile(r'\s*<div[^>]*class="user_icon(?:_reply)?"[^>]*></div>\s*', re.IGNORECASE)
PRINT_ONLY_NODE = re.compile(
    r'\s*<(span|div)\b[^>]*class="[^"]*\bprint-only\b[^"]*"[^>]*>.*?</\1>\s*',
    re.IGNORECASE | re.DOTALL,
)
AVATAR_CSS_RULE = re.compile(
    r'\s*\.message-container \.user_icon(?:_reply)? \{.*?\}\s*',
    re.DOTALL,
)
USER_EMAIL_CSS_RULE = re.compile(
    r'\s*\.message-container \.user-email \{.*?\}\s*',
    re.DOTALL,
)
PRINT_ONLY_CSS_RULE = re.compile(
    r'\s*@media screen \{\s*\.print-only \{.*?\}\s*\}\s*',
    re.DOTALL,
)


def slim_html(text: str) -> str:
    text = USER_AVATAR_IMG.sub("\n", text)
    text = USER_AVATAR_PLACEHOLDER.sub("\n", text)
    text = PRINT_ONLY_NODE.sub("\n", text)
    text = AVATAR_CSS_RULE.sub("\n", text)
    text = USER_EMAIL_CSS_RULE.sub("\n", text)
    text = PRINT_ONLY_CSS_RULE.sub("\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def main(argv):
    if len(argv) != 1:
        print("Usage: strip_export_html.py <dist_dir>", file=sys.stderr)
        return 1

    dist_dir = Path(argv[0]).resolve()
    if not dist_dir.is_dir():
        print(f"Error: not a directory: {dist_dir}", file=sys.stderr)
        return 1

    for path in sorted(dist_dir.rglob("*")):
        if path.suffix not in {".html", ".css"}:
            continue

        original = path.read_text(encoding="utf-8")
        slimmed = slim_html(original)
        if slimmed != original:
            path.write_text(slimmed, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
