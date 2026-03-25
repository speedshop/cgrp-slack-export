#!/usr/bin/env python3

import html
import json
import os
import re
import shutil
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

DATE_FILE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.json$")
USER_LINK = re.compile(r"<@([A-Z0-9]+)(?:\|([^>]+))?>")
CHANNEL_LINK = re.compile(r"<#([A-Z0-9]+)\|([^>]+)>")
SPECIAL_LINK = re.compile(r"<!([^>]+)>")
SUBTEAM_LINK = re.compile(r"<!subteam\^[^|>]+\|([^>]+)>")
LABELED_LINK = re.compile(r"<(https?://[^>|]+|mailto:[^>|]+)\|([^>]+)>")
BARE_LINK = re.compile(r"<(https?://[^>]+|mailto:[^>]+)>")


def read_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_users(archive_dir: Path):
    users = {}
    users_path = archive_dir / "users.json"
    if not users_path.exists():
        return users

    for user in read_json(users_path):
        profile = user.get("profile") or {}
        users[user.get("id")] = {
            "display_name": profile.get("display_name") or "",
            "real_name": profile.get("real_name") or user.get("real_name") or "",
            "name": user.get("name") or "",
        }
    return users


def load_channels(archive_dir: Path):
    channels = {}
    channels_path = archive_dir / "channels.json"
    if not channels_path.exists():
        return channels

    for channel in read_json(channels_path):
        channel_id = channel.get("id")
        if channel_id:
            channels[channel_id] = channel.get("name") or channel_id
    return channels


def resolve_user_name(message, users):
    profile = message.get("user_profile") or {}
    candidates = [
        profile.get("display_name"),
        profile.get("real_name"),
        profile.get("name"),
    ]

    user_id = message.get("user") or message.get("bot_id")
    if user_id in users:
        user = users[user_id]
        candidates.extend([
            user.get("display_name"),
            user.get("real_name"),
            user.get("name"),
        ])

    for candidate in candidates:
        if candidate:
            return candidate

    return user_id or "unknown"


def slack_special(match: re.Match[str]) -> str:
    token = match.group(1)
    replacements = {
        "channel": "@channel",
        "here": "@here",
        "everyone": "@everyone",
        "channel|@channel": "@channel",
        "here|@here": "@here",
        "everyone|@everyone": "@everyone",
    }
    return replacements.get(token, token)


def format_text(text: str, users, channels) -> str:
    if not text:
        return ""

    text = html.unescape(text).replace("\r\n", "\n")
    text = SUBTEAM_LINK.sub(lambda match: match.group(1), text)
    text = USER_LINK.sub(lambda match: f"@{users.get(match.group(1), {}).get('display_name') or users.get(match.group(1), {}).get('real_name') or match.group(2) or match.group(1)}", text)
    text = CHANNEL_LINK.sub(lambda match: f"#{channels.get(match.group(1)) or match.group(2)}", text)
    text = SPECIAL_LINK.sub(slack_special, text)
    text = LABELED_LINK.sub(lambda match: f"[{match.group(2)}]({match.group(1)})", text)
    text = BARE_LINK.sub(lambda match: f"<{match.group(1)}>", text)
    return text.strip()


def ts_to_datetime(ts):
    return datetime.fromtimestamp(float(ts))


def include_message(message):
    return not message.get("hidden")


def render_attachments(message, users, channels):
    lines = []

    attachments = message.get("attachments") or []
    if attachments:
        lines.append("**Attachments**")
        for attachment in attachments:
            title = attachment.get("title") or attachment.get("fallback") or "Untitled attachment"
            title_link = attachment.get("title_link")
            if title_link:
                line = f"- [{title}]({title_link})"
            else:
                line = f"- {title}"

            text = format_text(attachment.get("text") or "", users, channels)
            if text:
                line += f": {text.replace(chr(10), ' ')}"

            lines.append(line)
        lines.append("")

    files = message.get("files") or []
    if files:
        lines.append("**Files**")
        for file_info in files:
            title = file_info.get("title") or file_info.get("name") or "Untitled file"
            url = file_info.get("permalink") or file_info.get("url_private") or file_info.get("url_private_download")
            if url:
                lines.append(f"- [{title}]({url})")
            else:
                lines.append(f"- {title}")
        lines.append("")

    reactions = message.get("reactions") or []
    if reactions:
        formatted = []
        for reaction in reactions:
            name = reaction.get("name") or "reaction"
            count = reaction.get("count")
            formatted.append(f":{name}: {count}" if count else f":{name}:")
        lines.append(f"_Reactions:_ {', '.join(formatted)}")
        lines.append("")

    return lines


def render_message(message, users, channels):
    dt = ts_to_datetime(message["ts"])
    timestamp = dt.strftime("%Y-%m-%d %H:%M:%S")
    author = resolve_user_name(message, users)
    heading = f"### {timestamp} — {author}"

    body_lines = [heading, ""]

    subtype = message.get("subtype")
    thread_ts = message.get("thread_ts")
    if subtype and subtype != "thread_broadcast":
        body_lines.append(f"_Subtype:_ `{subtype}`")
    if thread_ts and thread_ts != message.get("ts"):
        body_lines.append(f"_Thread reply to:_ `{thread_ts}`")
    if len(body_lines) > 2:
        body_lines.append("")

    text = format_text(message.get("text") or "", users, channels)
    if text:
        body_lines.append(text)
        body_lines.append("")

    body_lines.extend(render_attachments(message, users, channels))
    body_lines.append("---")
    body_lines.append("")
    return "\n".join(body_lines)


def export_month(channel_name: str, month: str, messages, output_path: Path, users, channels):
    output_path.parent.mkdir(parents=True, exist_ok=True)

    sorted_messages = sorted(messages, key=lambda message: float(message["ts"]), reverse=True)
    day_groups = defaultdict(list)
    for message in sorted_messages:
        day_groups[message["_export_day"]].append(message)

    start_date = min(day_groups.keys())
    end_date = max(day_groups.keys())

    parts = [
        "---",
        f"channel: {channel_name}",
        f"period: {month}",
        f"start_date: {start_date}",
        f"end_date: {end_date}",
        f"message_count: {len(sorted_messages)}",
        "order: newest_first",
        "---",
        "",
        f"# #{channel_name} — {month}",
        "",
    ]

    for day in sorted(day_groups.keys(), reverse=True):
        parts.append(f"## {day}")
        parts.append("")
        for message in day_groups[day]:
            parts.append(render_message(message, users, channels))

    output_path.write_text("\n".join(parts).rstrip() + "\n", encoding="utf-8")
    return {
        "channel": channel_name,
        "month": month,
        "path": output_path,
        "message_count": len(sorted_messages),
    }


def write_index(index_path: Path, exports):
    lines = [
        "# Slack export markdown corpus",
        "",
        "This markdown export is optimized for qmd.",
        "Index the `markdown/` directory as your collection root.",
        "",
    ]

    by_channel = defaultdict(list)
    for export in exports:
        by_channel[export["channel"]].append(export)

    for channel in sorted(by_channel.keys()):
        lines.append(f"## #{channel}")
        lines.append("")
        for export in sorted(by_channel[channel], key=lambda item: item["month"], reverse=True):
            relative_path = export["path"].relative_to(index_path.parent)
            lines.append(
                f"- [{export['month']}]({relative_path.as_posix()}) — {export['message_count']} messages"
            )
        lines.append("")

    index_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main(argv):
    if len(argv) != 2:
        print("Usage: export_qmd.py <archive_dir> <dist_dir>", file=sys.stderr)
        return 1

    archive_dir = Path(argv[0]).resolve()
    dist_dir = Path(argv[1]).resolve()
    markdown_dir = dist_dir / "markdown"

    if markdown_dir.exists():
        shutil.rmtree(markdown_dir)
    markdown_dir.mkdir(parents=True, exist_ok=True)

    users = load_users(archive_dir)
    channels = load_channels(archive_dir)
    exports = []

    for channel_dir in sorted(path for path in archive_dir.iterdir() if path.is_dir()):
        month_messages = defaultdict(list)

        for day_file in sorted(channel_dir.iterdir()):
            match = DATE_FILE.match(day_file.name)
            if not match:
                continue

            export_day = match.group(1)
            month = export_day[:7]
            for message in read_json(day_file):
                if include_message(message) and message.get("ts"):
                    message["_export_day"] = export_day
                    month_messages[month].append(message)

        for month, messages in sorted(month_messages.items(), reverse=True):
            export_path = markdown_dir / channel_dir.name / f"{month}.md"
            exports.append(export_month(channel_dir.name, month, messages, export_path, users, channels))

    write_index(dist_dir / "archive.md", exports)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
