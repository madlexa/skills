"""niblet metrics — read and aggregate skill/pipeline usage from JSONL."""

import json
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


def metrics_file(project_root: Path | str, kind: str = "skills") -> Path:
    return Path(project_root).resolve() / ".niblet" / "metrics" / f"{kind}.jsonl"


def append_event(project_root: Path | str, kind: str, record: dict) -> Path:
    path = metrics_file(project_root, kind)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return path


def _parse_ts(ts: str) -> datetime:
    # ISO 8601 with timezone, possibly with microseconds.
    return datetime.fromisoformat(ts)


def aggregate(
    project_root: Path | str,
    kind: str = "skills",
    window_days: int = 30,
) -> list[dict]:
    """Aggregate metrics for each skill/pipeline.

    Returns list of dicts: name, usage_count, success_count, success_rate, last_used.
    """
    path = metrics_file(project_root, kind)
    if not path.exists():
        return []

    cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    counts = defaultdict(lambda: {"usage": 0, "success": 0, "last_used": None})

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue

            ts_str = record.get("ts", "")
            try:
                ts = _parse_ts(ts_str)
            except (ValueError, TypeError):
                continue

            if ts < cutoff:
                continue

            name = record.get("skill") or record.get("pipeline")
            if not name:
                continue

            entry = counts[name]
            entry["usage"] += 1
            if record.get("success"):
                entry["success"] += 1
            if entry["last_used"] is None or ts > entry["last_used"]:
                entry["last_used"] = ts

    result = []
    for name, data in sorted(counts.items()):
        usage = data["usage"]
        success = data["success"]
        success_rate = success / usage if usage > 0 else 0.0
        result.append(
            {
                "name": name,
                "usage_count": usage,
                "success_count": success,
                "success_rate": success_rate,
                "last_used": data["last_used"].isoformat() if data["last_used"] else None,
            }
        )
    return result


def flag_for_review(
    aggregates: list[dict],
    min_usage: int = 3,
    max_success_rate: float = 0.5,
) -> list[dict]:
    """Return artifacts that look unhealthy."""
    return [
        a
        for a in aggregates
        if a["usage_count"] >= min_usage and a["success_rate"] < max_success_rate
    ]
