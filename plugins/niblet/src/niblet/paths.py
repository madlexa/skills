"""niblet path resolution — mirrors lib/paths.sh in Python."""

import os
import subprocess
from pathlib import Path


def project_root(cwd: Path | str | None = None) -> Path:
    """Return project root: git toplevel if available, else cwd."""
    if cwd is None:
        cwd = Path.cwd()
    else:
        cwd = Path(cwd).resolve()
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip()).resolve()
    except FileNotFoundError:
        pass
    return cwd


def runtime() -> str:
    """Detect AI runtime: claude or kimi."""
    explicit = os.environ.get("NIBLET_RUNTIME", "")
    if explicit in ("claude", "kimi"):
        return explicit

    if os.environ.get("CLAUDE_CODE_SESSION") or os.environ.get("CLAUDE_PROJECT_DIR"):
        return "claude"
    if os.environ.get("KIMI_SESSION") or os.environ.get("KIMI_HOME") or os.environ.get("KIMI_WORK_DIR"):
        return "kimi"

    cwd = Path.cwd()
    if (cwd / ".kimi").exists() and not (cwd / ".claude").exists():
        return "kimi"
    if (cwd / ".claude").exists() and not (cwd / ".kimi").exists():
        return "claude"

    return "claude"


def runtime_home(rt: str | None = None) -> Path:
    """Return the runtime's home directory."""
    if rt is None:
        rt = runtime()
    if rt == "kimi":
        return Path(os.environ.get("KIMI_HOME", Path.home() / ".kimi"))
    return Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude"))


def store(project_root: Path | str) -> Path:
    """Return the niblet store directory inside a project."""
    return Path(project_root).resolve() / ".niblet"


def artifact_dir(kind: str, scope: str, project_root: Path | str) -> Path:
    """Return artifact directory for a given kind and scope.

    kind ∈ {kb, skills, commands, agents, scripts, memory}
    scope ∈ {project, global}
    """
    project_root = Path(project_root).resolve()
    rt = runtime()
    rt_home = runtime_home(rt)

    # Project-scope artifacts live under .claude/ for both runtimes.
    project_base = project_root / ".claude"
    global_base = rt_home / ".kimi" if rt == "kimi" else rt_home / ".claude"

    base = global_base if scope == "global" else project_base

    mapping = {
        "kb": "kb",
        "skills": "skills/niblet",
        "commands": "commands/niblet",
        "agents": "agents/niblet",
        "scripts": "scripts/niblet",
        "memory": "memory",
    }
    return base / mapping.get(kind, kind)


def claude_md_path(project_root: Path | str) -> Path:
    return Path(project_root).resolve() / "CLAUDE.md"


def agents_md_path(project_root: Path | str) -> Path:
    return Path(project_root).resolve() / "AGENTS.md"
