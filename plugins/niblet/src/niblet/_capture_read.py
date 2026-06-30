"""Record file reads/edits/writes and auto-trigger code-walker when a component
has been explored enough.

This is the Kimi-side equivalent of the Claude hook path: every time an agent
reads or edits a file, niblet learns that the component is active. Once a
component reaches the read/edit threshold and the cooldown has passed, a
code-walker queue entry is created so a future prompt can spawn the
niblet-code-walker sub-agent to distill component-level KB entries.
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def component_for_path(project_root: Path, file_path: str) -> str | None:
    """Map a project-relative path to a component slug.

    The component is the top-level directory under the project root.
    Paths inside meta directories (.niblet, .claude, .kimi, .git, node_modules)
    are ignored. Root-level files map to ``_root``.
    """
    if not file_path:
        return None

    ignored_prefixes = (".niblet", ".claude", ".kimi", ".git", "node_modules")
    parts = Path(file_path).parts
    if not parts:
        return None
    first = parts[0]
    if first in ignored_prefixes:
        return None
    return first


def counts_file(store: Path, session: str) -> Path:
    return store / "sessions" / session / "component_counts.json"


def load_counts(store: Path, session: str) -> dict:
    path = counts_file(store, session)
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_counts(store: Path, session: str, counts: dict) -> Path:
    path = counts_file(store, session)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(counts, f, ensure_ascii=False)
    tmp.replace(path)
    return path


def threshold() -> int:
    raw = os.environ.get("NIBLET_CODE_WALKER_THRESHOLD", "5")
    try:
        return max(1, int(raw))
    except ValueError:
        return 5


def cooldown_hours() -> int:
    raw = os.environ.get("NIBLET_CODE_WALKER_COOLDOWN_HOURS", "24")
    try:
        return max(0, int(raw))
    except ValueError:
        return 24


def queue_file_exists(queue_dir: Path, component: str) -> bool:
    """Return True if a queue or claimed entry for this component already exists."""
    if not queue_dir.exists():
        return False
    pattern = re.compile(rf"[-.]{re.escape(component)}(\.queue|\.claimed-.*)$")
    for entry in queue_dir.iterdir():
        if entry.is_file() and pattern.search(entry.name):
            return True
    return False


def cooldown_elapsed(store: Path, hours: int) -> bool:
    if hours == 0:
        return True
    marker = store / ".code-walker-last-run"
    if not marker.exists():
        return True
    age_seconds = time.time() - marker.stat().st_mtime
    return age_seconds >= hours * 3600


def queue_code_walker(store: Path, session: str, component: str) -> Path:
    queue_dir = store / "code_walker_queue"
    queue_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    safe_component = re.sub(r"[^a-zA-Z0-9._-]", "_", component)[:64]
    queue_file = queue_dir / f"{ts}-{safe_component}.queue"
    queue_file.write_text(
        f"session_id={session}\ncomponent={safe_component}\ntriggered_at={ts}\n",
        encoding="utf-8",
    )
    marker = store / ".code-walker-last-run"
    marker.touch()
    return queue_file


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="niblet-capture-read", description="Capture a read/edit event and maybe trigger code-walker"
    )
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--path", required=True, help="project-relative file path")
    parser.add_argument("--tool", default="Read", choices=["Read", "Edit", "Write", "MultiEdit", "NotebookEdit"])
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    store = project_root / ".niblet"

    component = component_for_path(project_root, args.path)
    if component is None:
        return 0

    counts = load_counts(store, args.session)
    counts[component] = counts.get(component, 0) + 1
    save_counts(store, args.session, counts)

    if counts[component] >= threshold() and cooldown_elapsed(store, cooldown_hours()):
        if not queue_file_exists(store / "code_walker_queue", component):
            queue_code_walker(store, args.session, component)
            print(f"code-walker queued for {component}")
            return 0

    return 0
