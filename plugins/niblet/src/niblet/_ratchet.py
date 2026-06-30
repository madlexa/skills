"""Autoresearch keep/discard loop for niblet proposals.

MVP heuristic:
- For UPDATE_* proposals on skills/commands/agents/scripts, look at the current
  artifact's success rate in metrics.
- If the current version is underperforming (usage >= 3, success_rate < 0.5),
  promote the proposal (assume it fixes the problem).
- Otherwise leave for human review.
- CREATE_* proposals always require human review.
"""

import argparse
import subprocess
import sys
from pathlib import Path

from niblet import metrics, proposals, versioning


def decision(action: str, name: str, aggregates: list[dict]) -> tuple[str, str]:
    """Return (decision, reason) for a proposal."""
    if action.startswith("CREATE_"):
        return "review", "CREATE_* proposals always require human review"

    if action not in (
        "UPDATE_SKILL",
        "UPDATE_AGENT",
        "UPDATE_COMMAND",
        "UPDATE_SCRIPT",
        "MERGE_SKILL",
        "MERGE_AGENT",
    ):
        return "review", f"{action} not handled by ratchet heuristic"

    data = next((a for a in aggregates if a["name"] == name), None)
    if data is None:
        return "review", "no metrics yet; cannot judge"

    usage = data["usage_count"]
    rate = data["success_rate"]
    if usage >= 3 and rate < 0.5:
        return "promote", f"current version underperforming ({usage} uses, {rate:.0%} success)"

    return "review", f"current version okay ({usage} uses, {rate:.0%} success)"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-ratchet", description="Ratchet loop for niblet proposals")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--dry-run", action="store_true", help="only show decisions")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    proposals_dir = project_root / ".niblet" / "proposals"

    if not proposals_dir.exists():
        print("no pending proposals")
        return 0

    script_dir = Path(__file__).resolve().parents[2] / "bin"
    aggregates = metrics.aggregate(project_root, kind="skills", window_days=30)
    pending = proposals.list_proposals(project_root)

    promoted = 0
    reviewed = 0
    for prop in pending:
        fm = proposals.parse_frontmatter(prop)
        action = fm.get("action", "")
        name = fm.get("name", "")
        scope = fm.get("scope", "project")
        if fm.get("rejected_reason"):
            continue

        dec, reason = decision(action, name, aggregates)
        print(f"{prop.name}: {action} {name} -> {dec} ({reason})")

        if dec == "promote" and not args.dry_run:
            if "target" not in fm:
                target = versioning.target_path(action, name, scope, project_root)
                proposals.inject_frontmatter_field(prop, "target", str(target))
            subprocess.run(
                [str(script_dir / "niblet-promote"), str(prop)],
                cwd=project_root,
                check=False,
            )
            promoted += 1
        else:
            reviewed += 1

    print(f"\nratchet summary: promoted={promoted}, review={reviewed}")
    return 0
