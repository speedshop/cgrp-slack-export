import importlib.util
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMPORTS_DIR = ROOT / "imports"
DATE_FILE = re.compile(r"(?:.*/)?([^/]+)/(\d{4}-\d{2}-\d{2})\.json$")


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


merge = load_module(ROOT / "lib/merge.py", "merge_module")
export_qmd = load_module(ROOT / "lib/export_qmd.py", "export_qmd_module")
strip_export_html = load_module(ROOT / "lib/strip_export_html.py", "strip_export_html_module")


def collect_boundaries(zip_paths):
    messages_by_channel = {}

    for zip_path in zip_paths:
        with zipfile.ZipFile(zip_path) as archive:
            for name in archive.namelist():
                match = DATE_FILE.match(name)
                if not match:
                    continue

                channel = match.group(1)
                if channel in merge.EXCLUDED_CHANNELS:
                    continue

                for message in json.loads(archive.read(name)):
                    if message.get("hidden") or not message.get("ts"):
                        continue

                    messages_by_channel.setdefault(channel, {})[str(message["ts"])] = message

    boundaries = {}
    for channel, messages in messages_by_channel.items():
        ordered = sorted(messages.values(), key=lambda message: merge.ts_key(message["ts"]))
        boundaries[channel] = {"first": ordered[0], "last": ordered[-1]}

    return boundaries


def slack_export_viewer_python():
    local_python = ROOT / ".venv-sev" / "bin" / "python"
    if local_python.exists():
        return str(local_python)

    viewer = shutil.which("slack-export-viewer")
    if not viewer:
        raise AssertionError("slack-export-viewer is not installed")

    with open(viewer, "r", encoding="utf-8") as handle:
        shebang = handle.readline().strip()

    if not shebang.startswith("#!"):
        raise AssertionError(f"Could not determine python interpreter for {viewer}")

    return shebang[2:]


def merge_imports_into(archive_dir: Path, zip_paths):
    for zip_path in zip_paths:
        subprocess.run(
            ["python3", str(ROOT / "lib/merge.py"), str(zip_path), str(archive_dir)],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )


def build_html_into(archive_dir: Path, dist_dir: Path):
    viewer_python = slack_export_viewer_python()
    wrapper = ROOT / "lib" / "slack_export_viewer_desc.py"

    subprocess.run(
        [
            viewer_python,
            str(wrapper),
            "viewer",
            "-z",
            str(archive_dir),
            "--html-only",
            "-o",
            str(dist_dir),
            "--no-browser",
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    with tempfile.TemporaryDirectory() as export_tmp:
        subprocess.run(
            [viewer_python, str(wrapper), "export", str(archive_dir)],
            check=True,
            cwd=export_tmp,
            capture_output=True,
            text=True,
        )

        html_files = list(Path(export_tmp).glob("*.html"))
        if len(html_files) != 1:
            raise AssertionError(f"Expected one exported HTML file, got {html_files}")

        dist_dir.mkdir(parents=True, exist_ok=True)
        (dist_dir / "archive-single.html").write_text(
            html_files[0].read_text(encoding="utf-8"),
            encoding="utf-8",
        )

    subprocess.run(
        [viewer_python, str(ROOT / "lib" / "strip_export_html.py"), str(dist_dir)],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )


def html_timestamp(message):
    return datetime.fromtimestamp(float(message["ts"])).strftime("%Y-%m-%d %H:%M:%S")


def run_in_viewer_python(script: str) -> str:
    result = subprocess.run(
        [slack_export_viewer_python(), "-c", script],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class TestExportHtmlTransforms(unittest.TestCase):
    def test_strip_export_html_removes_avatars_and_print_only_nodes(self):
        html = '''
<div class="message-container">
  <img src="avatar.png" class="user_icon" loading="lazy" />
  <div class="username">Alice <span class="print-only user-email">(alice@example.com)</span></div>
  <div class="print-only">Original URL: https://example.com</div>
</div>
<style>
.message-container .user_icon { width: 50px; }
.message-container .user_icon_reply { width: 45px; }
.message-container .user-email { font-style: italic; }
@media screen {
    .print-only { display: none }
}
</style>
'''
        slimmed = strip_export_html.slim_html(html)
        self.assertNotIn('class="user_icon"', slimmed)
        self.assertNotIn('print-only', slimmed)
        self.assertNotIn('.user_icon', slimmed)
        self.assertNotIn('.user-email', slimmed)

    def test_message_text_escapes_named_capture_syntax(self):
        rendered = run_in_viewer_python(
            f'''
import importlib.util
from pathlib import Path
path = Path({str(ROOT / "lib" / "slack_export_viewer_desc.py")!r})
spec = importlib.util.spec_from_file_location("viewer_desc_module", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
message = module.Message(None, {{"ts": "0", "text": "", "user": "U"}}, "C", "archive")
print(message._format_rich_text_element({{"type": "text", "text": "Regex example /(?<a>\\\\w+) (?<b>\\\\w+)/"}}))
'''
        )
        self.assertIn('/(?&lt;a&gt;\\w+) (?&lt;b&gt;\\w+)/', rendered)
        self.assertNotIn('/(?<a>\\w+) (?<b>\\w+)/', rendered)

    def test_message_text_escapes_literal_html_tags(self):
        rendered = run_in_viewer_python(
            f'''
import importlib.util
from pathlib import Path
path = Path({str(ROOT / "lib" / "slack_export_viewer_desc.py")!r})
spec = importlib.util.spec_from_file_location("viewer_desc_module", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
message = module.Message(None, {{"ts": "0", "text": "", "user": "U"}}, "C", "archive")
print(message._format_rich_text_element({{"type": "text", "text": "Cloudflare touched <option> and <template> tags"}}))
'''
        )
        self.assertIn('&lt;option&gt;', rendered)
        self.assertIn('&lt;template&gt;', rendered)
        self.assertNotIn('<option>', rendered)
        self.assertNotIn('<template>', rendered)


@unittest.skipUnless(os.environ.get("FULL_EXPORT_TESTS") == "1", "set FULL_EXPORT_TESTS=1 to run full export integration tests")
class TestExportQmd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.zip_paths = sorted(IMPORTS_DIR.glob("*.zip"))
        if not cls.zip_paths:
            raise AssertionError("No import zips found in imports/")

        cls.expected_boundaries = collect_boundaries(cls.zip_paths)
        cls.tempdir = tempfile.TemporaryDirectory()
        cls.archive_dir = Path(cls.tempdir.name) / "archive"
        cls.dist_dir = Path(cls.tempdir.name) / "dist"

        merge_imports_into(cls.archive_dir, cls.zip_paths)
        build_html_into(cls.archive_dir, cls.dist_dir)

        subprocess.run(
            ["python3", str(ROOT / "lib/export_qmd.py"), str(cls.archive_dir), str(cls.dist_dir)],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

        cls.users = export_qmd.load_users(cls.archive_dir)
        cls.channels = export_qmd.load_channels(cls.archive_dir)
        cls.single_html = (cls.dist_dir / "archive-single.html").read_text(encoding="utf-8")
        cls.general_html = (cls.dist_dir / "channel" / "general" / "index.html").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.tempdir.cleanup()

    def test_export_contains_first_and_last_message_for_each_channel(self):
        missing = []

        for channel, boundaries in sorted(self.expected_boundaries.items()):
            channel_dir = self.dist_dir / "markdown" / channel
            self.assertTrue(channel_dir.is_dir(), f"Missing exported channel directory: {channel_dir}")

            corpus = "\n".join(
                path.read_text(encoding="utf-8")
                for path in sorted(channel_dir.glob("*.md"))
            )

            for label, message in boundaries.items():
                rendered = export_qmd.render_message(message, self.users, self.channels).strip()
                if rendered not in corpus:
                    missing.append(
                        f"{channel} {label} ts={message.get('ts')} subtype={message.get('subtype')}"
                    )

        self.assertFalse(
            missing,
            "Missing boundary messages in markdown export:\n- " + "\n- ".join(missing),
        )

    def test_html_exports_contain_first_and_last_message_for_each_channel(self):
        missing = []

        for channel, boundaries in sorted(self.expected_boundaries.items()):
            channel_html_path = self.dist_dir / "channel" / channel / "index.html"
            self.assertTrue(channel_html_path.is_file(), f"Missing channel HTML: {channel_html_path}")
            channel_html = channel_html_path.read_text(encoding="utf-8")

            for label, message in boundaries.items():
                timestamp = html_timestamp(message)
                if timestamp not in channel_html:
                    missing.append(f"channel page missing {channel} {label} ts={message['ts']} ({timestamp})")
                if timestamp not in self.single_html:
                    missing.append(f"single export missing {channel} {label} ts={message['ts']} ({timestamp})")

        self.assertFalse(
            missing,
            "Missing boundary messages in HTML exports:\n- " + "\n- ".join(missing),
        )

    def test_html_escapes_literal_tag_text_in_messages(self):
        self.assertIn("2026-02-20 13:18:51", self.general_html)
        self.assertIn("&lt;option&gt; tags, and replaced them with a &lt;template&gt; tag", self.general_html)
        self.assertNotIn("the email addresses from the <option> tags", self.general_html)
        self.assertNotIn("replaced them with a <template> tag", self.general_html)
        self.assertIn("2026-02-21 00:17:06", self.general_html)

    def test_html_escapes_named_capture_syntax_in_messages(self):
        self.assertIn("2021-04-12 01:47:47", self.general_html)
        self.assertIn("/(?&lt;a&gt;\\w+) (?&lt;b&gt;\\w+)/, :a", self.general_html)
        self.assertNotIn("/(?<a>\\w+) (?<b>\\w+)/, :a", self.general_html)
        self.assertIn("2021-04-12 22:42:24", self.general_html)

    def test_html_strips_avatars_and_print_only_nodes(self):
        for html in (self.general_html, self.single_html):
            self.assertNotIn("class=\"user_icon\"", html)
            self.assertNotIn("class=\"user_icon_reply\"", html)
            self.assertNotIn("print-only", html)


if __name__ == "__main__":
    unittest.main()
