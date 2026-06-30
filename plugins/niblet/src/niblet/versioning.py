"""niblet file-based versioning — keep/discard without git."""

import shutil
from datetime import datetime, timezone
from pathlib import Path

from .paths import agents_md_path, artifact_dir, claude_md_path


def kind_for_action(action: str) -> str:
    """Map action to artifact kind."""
    mapping = {
        "CREATE_SKILL": "skills",
        "UPDATE_SKILL": "skills",
        "MERGE_SKILL": "skills",
        "CREATE_AGENT": "agents",
        "UPDATE_AGENT": "agents",
        "MERGE_AGENT": "agents",
        "CREATE_COMMAND": "commands",
        "UPDATE_COMMAND": "commands",
        "CREATE_SCRIPT": "scripts",
        "UPDATE_SCRIPT": "scripts",
        "ADD_KB_ENTRY": "kb",
        "MERGE_KB_ENTRY": "kb",
        "UPDATE_KB_ENTRY": "kb",
        "DEPRECATE_KB_ENTRY": "kb",
        "UPDATE_MEMORY": "memory",
    }
    return mapping.get(action, "")


def target_path(action: str, name: str, scope: str, project_root: Path | str) -> Path:
    """Resolve the live target path for an action/name."""
    project_root = Path(project_root).resolve()
    kind = kind_for_action(action)
    base = artifact_dir(kind, scope, project_root)

    if action in ("CREATE_SKILL", "UPDATE_SKILL", "MERGE_SKILL"):
        return base / name / "SKILL.md"
    if action in ("CREATE_AGENT", "UPDATE_AGENT", "MERGE_AGENT", "CREATE_COMMAND", "UPDATE_COMMAND"):
        return base / f"{name}.md"
    if action in ("CREATE_SCRIPT", "UPDATE_SCRIPT"):
        return base / name
    if action in ("ADD_KB_ENTRY", "MERGE_KB_ENTRY", "UPDATE_KB_ENTRY", "DEPRECATE_KB_ENTRY"):
        path = base / name
        if not str(path).endswith(".md"):
            path = path.with_suffix(".md")
        return path
    if action == "UPDATE_MEMORY":
        path = base / name
        if not str(path).endswith(".md"):
            path = path.with_suffix(".md")
        return path
    if action == "UPDATE_CLAUDE":
        return claude_md_path(project_root)
    if action == "UPDATE_AGENTS":
        return agents_md_path(project_root)

    raise ValueError(f"Cannot resolve target for action: {action}")


def versions_dir(action: str, name: str, project_root: Path | str) -> Path:
    """Return the version storage directory for an artifact."""
    project_root = Path(project_root).resolve()
    kind = kind_for_action(action)
    if action in ("UPDATE_CLAUDE", "UPDATE_AGENTS"):
        kind = "claude-md" if action == "UPDATE_CLAUDE" else "agents-md"
    return store_versions_dir(project_root) / kind / name


def store_versions_dir(project_root: Path | str) -> Path:
    return Path(project_root).resolve() / ".niblet" / "versions"


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def save_version(action: str, name: str, scope: str, project_root: Path | str) -> Path | None:
    """Save the current live version of an artifact before overwriting.

    Returns the version file path, or None if the live file does not exist.
    """
    live = target_path(action, name, scope, project_root)
    if not live.exists():
        return None
    vdir = versions_dir(action, name, project_root)
    vdir.mkdir(parents=True, exist_ok=True)
    vfile = vdir / f"{timestamp()}.md"
    shutil.copy2(live, vfile)
    return vfile


def list_versions(action: str, name: str, project_root: Path | str) -> list[Path]:
    """Return sorted list of version files for an artifact."""
    vdir = versions_dir(action, name, project_root)
    if not vdir.exists():
        return []
    return sorted(vdir.glob("*.md"))


def restore_version(action: str, name: str, ts: str, scope: str, project_root: Path | str) -> Path:
    """Restore a specific version back to the live target path."""
    vdir = versions_dir(action, name, project_root)
    vfile = vdir / f"{ts}.md"
    if not vfile.exists():
        raise FileNotFoundError(f"Version not found: {vfile}")
    live = target_path(action, name, scope, project_root)
    live.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(vfile, live)
    return live
