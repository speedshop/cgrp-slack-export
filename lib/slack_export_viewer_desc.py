#!/usr/bin/env python3

import glob
import io
import json
import os
import sys
from copy import deepcopy
from html import escape
from html.parser import HTMLParser

from slackviewer.cli import cli
from slackviewer.formatter import SlackFormatter
from slackviewer.main import main
from slackviewer.message import Message
from slackviewer.reader import Reader


ALLOWED_HTML_TAGS = {
    "a": {"href"},
    "b": set(),
    "blockquote": set(),
    "br": set(),
    "code": set(),
    "em": set(),
    "i": set(),
    "img": {"src", "alt", "title"},
    "li": set(),
    "ol": set(),
    "p": set(),
    "pre": set(),
    "small": set(),
    "strong": set(),
    "ul": set(),
}
VOID_HTML_TAGS = {"br", "img"}


class SafeMessageHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in ALLOWED_HTML_TAGS:
            allowed_attrs = ALLOWED_HTML_TAGS[tag]
            rendered_attrs = []
            for name, value in attrs:
                if name in allowed_attrs and value is not None:
                    rendered_attrs.append(f' {name}="{escape(value, quote=True)}"')
            self.parts.append(f'<{tag}{"".join(rendered_attrs)}>')
        else:
            self.parts.append(escape(self.get_starttag_text()))

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag in ALLOWED_HTML_TAGS and tag not in VOID_HTML_TAGS:
            self.parts.append(f"</{tag}>")
        else:
            self.parts.append(escape(f"</{tag}>"))

    def handle_data(self, data):
        self.parts.append(escape(data))

    def handle_entityref(self, name):
        self.parts.append(f"&{name};")

    def handle_charref(self, name):
        self.parts.append(f"&#{name};")

    def handle_comment(self, data):
        self.parts.append(escape(f"<!--{data}-->"))

    def handle_decl(self, decl):
        self.parts.append(escape(f"<!{decl}>"))

    def unknown_decl(self, data):
        self.parts.append(escape(f"<!{data}>"))

    def render(self):
        return "".join(self.parts)


def sanitize_message_html(fragment):
    parser = SafeMessageHTML()
    parser.feed(fragment)
    parser.close()
    return parser.render()


_original_render_text = SlackFormatter.render_text
_original_format_rich_text_element = Message._format_rich_text_element
_original_format_block_type = Message._format_block_type


def render_text_safe(self, message, process_markdown=True):
    return sanitize_message_html(_original_render_text(self, message, process_markdown))


def format_rich_text_element_safe(self, element):
    if element.get("type") == "text":
        safe_element = deepcopy(element)
        safe_element["text"] = escape(safe_element.get("text", ""), quote=False)
        return _original_format_rich_text_element(self, safe_element)

    if element.get("type") == "link":
        safe_element = deepcopy(element)
        if "text" in safe_element:
            safe_element["text"] = escape(safe_element["text"], quote=False)
        safe_element["url"] = escape(safe_element["url"], quote=True)
        return _original_format_rich_text_element(self, safe_element)

    return _original_format_rich_text_element(self, element)


def format_block_type_safe(self, text_obj, b_type):
    safe_text_obj = deepcopy(text_obj)

    if isinstance(safe_text_obj.get("text"), str):
        safe_text_obj["text"] = escape(safe_text_obj["text"], quote=False)
    elif isinstance(safe_text_obj.get("text"), dict) and isinstance(safe_text_obj["text"].get("text"), str):
        safe_text_obj["text"] = dict(safe_text_obj["text"])
        safe_text_obj["text"]["text"] = escape(safe_text_obj["text"]["text"], quote=False)

    for key in ("image_url", "alt_text"):
        if isinstance(safe_text_obj.get(key), str):
            safe_text_obj[key] = escape(safe_text_obj[key], quote=True)

    return _original_format_block_type(self, safe_text_obj, b_type)


SlackFormatter.render_text = render_text_safe
Message._format_rich_text_element = format_rich_text_element_safe
Message._format_block_type = format_block_type_safe


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
