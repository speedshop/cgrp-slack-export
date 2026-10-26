#!/usr/bin/env python3

import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

from merge import EXCLUDED_CHANNELS, abort, ts_key, write_json

API_ROOT = "https://slack.com/api/"
EXPORT_TZ = ZoneInfo("America/Los_Angeles")
THREAD_LOOKBACK = datetime.timedelta(days=90)


def slack_get(token: str, method: str, params):
    url = API_ROOT + method + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})

    while True:
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code == 429:
                time.sleep(int(exc.headers.get("Retry-After", "5")))
                continue
            raise

        if not payload.get("ok"):
            abort(f"Slack API {method} failed: {payload.get('error')}")
        return payload


def paginate(token: str, method: str, params, key: str):
    cursor = ""
    while True:
        payload = slack_get(token, method, {**params, "cursor": cursor} if cursor else params)
        yield from payload.get(key, [])
        cursor = (payload.get("response_metadata") or {}).get("next_cursor")
        if not cursor:
            return


def fetch_channel_messages(token: str, channel_id: str, since: float):
    oldest = since - THREAD_LOOKBACK.total_seconds()
    history = list(paginate(
        token,
        "conversations.history",
        {"channel": channel_id, "oldest": f"{oldest:.6f}", "limit": 999},
        "messages",
    ))

    messages = {message["ts"]: message for message in history if float(message["ts"]) >= since}

    for parent in history:
        if not parent.get("reply_count") or float(parent.get("latest_reply", 0)) < since:
            continue

        thread = paginate(
            token,
            "conversations.replies",
            {"channel": channel_id, "ts": parent["ts"], "limit": 999},
            "messages",
        )
        replies = [message for message in thread if message["ts"] != parent["ts"]]
        parent["replies"] = [{"user": reply.get("user"), "ts": reply["ts"]} for reply in replies]
        messages[parent["ts"]] = parent

        for reply in replies:
            if float(reply["ts"]) >= since:
                messages[reply["ts"]] = reply

    return messages.values()


def export_day(ts: str) -> str:
    return datetime.datetime.fromtimestamp(float(ts), EXPORT_TZ).date().isoformat()


def write_channel(output_dir: str, channel_name: str, messages) -> int:
    by_day = {}
    for message in messages:
        by_day.setdefault(export_day(message["ts"]), []).append(message)

    for day, day_messages in by_day.items():
        day_messages.sort(key=lambda message: ts_key(message["ts"]))
        write_json(os.path.join(output_dir, channel_name, f"{day}.json"), day_messages)

    return len(by_day)


def previous_month_start() -> datetime.date:
    first_of_month = datetime.datetime.now(EXPORT_TZ).date().replace(day=1)
    return (first_of_month - datetime.timedelta(days=1)).replace(day=1)


def usage() -> str:
    return (
        "Usage: mise run fetch -- <output-dir> [--since YYYY-MM-DD]\n\n"
        "Writes a Slack-export-format directory from the Slack Web API.\n"
        "Fetches public channel messages and thread replies posted since the given\n"
        "date (default: first day of the previous month, America/Los_Angeles).\n"
        "Requires SLACK_TOKEN."
    )


def main(argv):
    if argv and argv[0] in {"-h", "--help"}:
        print(usage())
        return 0

    if len(argv) not in {1, 3} or (len(argv) == 3 and argv[1] != "--since"):
        print(usage(), file=sys.stderr)
        return 1

    token = os.environ.get("SLACK_TOKEN")
    if not token:
        abort("Missing SLACK_TOKEN")

    output_dir = os.path.abspath(argv[0])
    since_date = datetime.date.fromisoformat(argv[2]) if len(argv) == 3 else previous_month_start()
    since = datetime.datetime.combine(since_date, datetime.time(), EXPORT_TZ).timestamp()

    print(f"Fetching Slack history since {since_date} into {output_dir}")

    users = list(paginate(token, "users.list", {"limit": 1000}, "members"))
    write_json(os.path.join(output_dir, "users.json"), users)
    print(f"users.json: {len(users)} users")

    channels = [
        channel
        for channel in paginate(
            token,
            "conversations.list",
            {"types": "public_channel", "exclude_archived": "true", "limit": 1000},
            "channels",
        )
        if channel["name"] not in EXCLUDED_CHANNELS
    ]
    write_json(os.path.join(output_dir, "channels.json"), channels)
    print(f"channels.json: {len(channels)} channels")

    for channel in channels:
        messages = fetch_channel_messages(token, channel["id"], since)
        days = write_channel(output_dir, channel["name"], messages)
        print(f"Channel {channel['name']}: {len(messages)} messages across {days} days")

    print(f"✅ Fetch complete: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
