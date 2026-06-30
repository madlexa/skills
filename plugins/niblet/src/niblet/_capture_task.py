"""Capture a completed agent task and its side effects."""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from niblet import metrics, pipelines


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def append_jsonl(path: Path, record: dict) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def write_task_record(store: Path, session_id: str, task: dict) -> Path:
    tasks_dir = store / "tasks"
    ensure_dir(tasks_dir)
    record = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "session": session_id,
        "summary": task.get("summary", ""),
        "components": task.get("components", []),
        "skills": task.get("skills", []),
        "files_read": task.get("files_read", []),
        "files_modified": task.get("files_modified", []),
        "outcome": task.get("outcome", "success"),
        "feedback": task.get("feedback", ""),
    }
    file_path = tasks_dir / f"{session_id}.jsonl"
    append_jsonl(file_path, record)
    return file_path


def write_skill_metrics(project_root: Path, session_id: str, skills: list, outcome: str) -> None:
    if not skills:
        return
    success = outcome == "success"
    for skill in skills:
        metrics.append_event(
            project_root,
            "skills",
            {
                "ts": datetime.now(timezone.utc).isoformat(),
                "session": session_id,
                "skill": skill,
                "event": "used",
                "success": success,
            },
        )


def write_feedback_memory(project_root: Path, feedback: str, outcome: str) -> Path | None:
    if not feedback or outcome not in ("failure", "cancelled"):
        return None
    memory_dir = project_root / ".claude" / "memory"
    ensure_dir(memory_dir)
    file_path = memory_dir / "feedback_task.md"
    ts = datetime.now(timezone.utc).isoformat()
    content = f"\n## {ts}\n\n{feedback}\n"
    with file_path.open("a", encoding="utf-8") as f:
        f.write(content)
    return file_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-capture-task", description="Capture a completed agent task")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--summary", default="")
    parser.add_argument("--components", default="", help="comma-separated component slugs")
    parser.add_argument("--skills", default="", help="comma-separated skill names")
    parser.add_argument("--pipeline", default="", help="pipeline used for this task")
    parser.add_argument("--files-read", default="", help="comma-relative file paths")
    parser.add_argument("--files-modified", default="", help="comma-relative file paths")
    parser.add_argument("--outcome", default="success", choices=["success", "failure", "cancelled"])
    parser.add_argument("--feedback", default="")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    if not project_root.is_dir():
        print(f"error: not a directory: {project_root}", file=sys.stderr)
        return 66

    store = project_root / ".niblet"
    ensure_dir(store)

    task = {
        "summary": args.summary,
        "components": [c.strip() for c in args.components.split(",") if c.strip()],
        "skills": [s.strip() for s in args.skills.split(",") if s.strip()],
        "files_read": [f.strip() for f in args.files_read.split(",") if f.strip()],
        "files_modified": [f.strip() for f in args.files_modified.split(",") if f.strip()],
        "outcome": args.outcome,
        "feedback": args.feedback,
    }

    task_path = write_task_record(store, args.session_id, task)
    write_skill_metrics(project_root, args.session_id, task["skills"], task["outcome"])
    if args.pipeline:
        pipelines.record_usage(
            project_root, args.session_id, args.pipeline, success=task["outcome"] == "success"
        )
    memory_path = write_feedback_memory(project_root, task["feedback"], task["outcome"])

    print(f"captured: {task_path}")
    if memory_path:
        print(f"feedback: {memory_path}")
    return 0
