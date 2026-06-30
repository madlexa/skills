"""niblet pipelines — reusable, named workflows.

Pipelines live under `.niblet/pipelines/` as markdown files with a simple
frontmatter envelope:

    ---
    name: ratchet-maintenance
    description: Review metrics and auto-promote underperforming artifacts.
    ---

    1. Run `niblet-metrics` to see current success rates.
    2. Run `niblet-ratchet --dry-run` to preview promotions.
    3. Run `niblet-ratchet` to apply promotions.

Usage is recorded in `.niblet/metrics/pipelines.jsonl` so the ratchet loop can
later decide whether a pipeline is helping or hurting.
"""

import re
from pathlib import Path

from .metrics import append_event


def pipelines_dir(project_root: Path | str) -> Path:
    return Path(project_root).resolve() / ".niblet" / "pipelines"


def _parse_frontmatter(text: str) -> dict:
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    fm = parts[1]
    result = {}
    for line in fm.splitlines():
        match = re.match(r"^([a-zA-Z0-9_]+)\s*:\s*(.*)$", line)
        if match:
            result[match.group(1)] = match.group(2).strip()
    return result


def list_pipelines(project_root: Path | str) -> list[dict]:
    """Return all discovered pipelines with name, description, and path."""
    pdir = pipelines_dir(project_root)
    if not pdir.exists():
        return []
    result = []
    for path in sorted(pdir.glob("*.md")):
        fm = _parse_frontmatter(path.read_text(encoding="utf-8"))
        result.append(
            {
                "name": fm.get("name", path.stem),
                "description": fm.get("description", ""),
                "path": str(path),
            }
        )
    return result


def load_pipeline(project_root: Path | str, name: str) -> dict | None:
    """Load a single pipeline by name."""
    for p in list_pipelines(project_root):
        if p["name"] == name:
            path = Path(p["path"])
            text = path.read_text(encoding="utf-8")
            parts = text.split("---", 2)
            body = parts[2] if len(parts) >= 3 else text
            return {"name": p["name"], "description": p["description"], "body": body, "path": str(path)}
    return None


def record_usage(project_root: Path | str, session_id: str, pipeline: str, success: bool) -> None:
    """Append a pipeline usage event to metrics."""
    from datetime import datetime, timezone

    append_event(
        project_root,
        "pipelines",
        {
            "ts": datetime.now(timezone.utc).isoformat(),
            "session": session_id,
            "pipeline": pipeline,
            "event": "used",
            "success": success,
        },
    )
