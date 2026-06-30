"""Print skill/pipeline usage and success rates."""

import argparse
import json
import sys
from pathlib import Path

from niblet import metrics


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-metrics", description="Show niblet skill/pipeline metrics")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--kind", default="skills", choices=["skills", "pipelines"])
    parser.add_argument("--window-days", type=int, default=30)
    parser.add_argument("--skill", help="show details for a single skill/pipeline")
    parser.add_argument("--json", action="store_true", help="output JSON instead of table")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    if not project_root.is_dir():
        print(f"error: not a directory: {project_root}", file=sys.stderr)
        return 66

    aggregates = metrics.aggregate(project_root, kind=args.kind, window_days=args.window_days)

    if args.skill:
        aggregates = [a for a in aggregates if a["name"] == args.skill]

    if args.json:
        print(json.dumps(aggregates, indent=2))
        return 0

    if not aggregates:
        print(f"No {args.kind} metrics found for the last {args.window_days} days.")
        return 0

    print(f"{'name':<40} {'usage':>6} {'success':>8} {'rate':>6} {'last_used'}")
    print("-" * 80)
    for a in aggregates:
        rate_pct = f"{a['success_rate'] * 100:.0f}%"
        last = a["last_used"][:19] if a["last_used"] else "never"
        print(
            f"{a['name']:<40} {a['usage_count']:>6} {a['success_count']:>8} {rate_pct:>6} {last}"
        )

    flagged = metrics.flag_for_review(aggregates)
    if flagged:
        print()
        print("Flagged for review (usage >= 3, success rate < 50%):")
        for a in flagged:
            print(f"  - {a['name']} ({a['success_count']}/{a['usage_count']})")

    return 0
