"""niblet proposal helpers — parse envelope frontmatter and payload."""

import re
from pathlib import Path


def parse_frontmatter(path: Path) -> dict:
    """Read the simple key:value frontmatter from a proposal file."""
    text = path.read_text(encoding="utf-8")
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


def extract_payload(text: str, strip_beginner_summary: bool = False) -> str:
    """Return the body of a proposal after the second ``---`` marker.

    When ``strip_beginner_summary`` is true, remove the optional
    ``<!-- NIBLET BEGINNER SUMMARY -->...<!-- END NIBLET BEGINNER SUMMARY -->``
    block that niblet-apply injects for human-readable context.
    """
    parts = text.split("---", 2)
    if len(parts) < 3:
        return text
    body = parts[2]
    if not strip_beginner_summary:
        return body

    lines = body.splitlines(keepends=True)
    out = []
    skip = False
    eat_blank = False
    for line in lines:
        if not skip and line.strip() == "<!-- NIBLET BEGINNER SUMMARY -->":
            skip = True
            continue
        if skip and line.strip() == "<!-- END NIBLET BEGINNER SUMMARY -->":
            skip = False
            eat_blank = True
            continue
        if skip:
            continue
        if eat_blank:
            eat_blank = False
            if line.strip() == "":
                continue
        out.append(line)
    return "".join(out)


def list_proposals(project_root: Path) -> list[Path]:
    """Return sorted pending proposal paths."""
    proposals_dir = project_root / ".niblet" / "proposals"
    if not proposals_dir.exists():
        return []
    return sorted(proposals_dir.glob("*.md"))


def inject_frontmatter_field(path: Path, key: str, value: str) -> None:
    """Add ``key: value`` right after the opening ``---`` of a proposal."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise ValueError("proposal has no frontmatter")
    new_text = text.replace("---\n", f"---\n{key}: {value}\n", 1)
    path.write_text(new_text, encoding="utf-8")
