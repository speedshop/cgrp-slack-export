#!/usr/bin/env python3

import glob
import io
import json
import os
import sys

from slackviewer.cli import cli
from slackviewer.formatter import SlackFormatter
from slackviewer.main import main
from slackviewer.message import Message
from slackviewer.reader import Reader


def create_messages_desc(self, names, data, isDms=False):
    chats = {}
    empty_dms = []
    formatter = SlackFormatter(self._Reader__USER_DATA, data)

    channel_name_to_id = {}
    for channel in data.values():
        if "name" in channel:
            channel_name_to_id[channel["name"]] = channel["id"]
        else:
            channel_name_to_id[channel["id"]] = channel["id"]

    for name in names:
        dir_path = os.path.join(self._PATH, name)
        messages = []
        day_files = glob.glob(os.path.join(dir_path, "*.json"))

        if not day_files:
            if isDms:
                empty_dms.append(name)
            continue

        for day in sorted(day_files, reverse=True):
            with io.open(os.path.join(self._PATH, day), encoding="utf8") as handle:
                day_messages = json.load(handle)
                day_messages.sort(key=Reader._extract_time, reverse=True)

                channel_id = channel_name_to_id[name]
                for raw_message in day_messages:
                    message = Message(formatter, raw_message, channel_id, self._slack_name)
                    if self._filter_user(message):
                        messages.append(message)

        chats[name] = messages

    chats = self._build_threads(chats)

    if isDms:
        self._EMPTY_DMS = empty_dms

    return chats


Reader._create_messages = create_messages_desc


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""

    if mode == "viewer":
        sys.argv = [sys.argv[0], *sys.argv[2:]]
        raise SystemExit(main())

    if mode == "export":
        sys.argv = [sys.argv[0], "export", *sys.argv[2:]]
        raise SystemExit(cli())

    print("Usage: slack_export_viewer_desc.py <viewer|export> [args...]", file=sys.stderr)
    raise SystemExit(1)
