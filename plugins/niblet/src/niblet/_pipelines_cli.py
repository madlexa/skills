"""CLI for listing and running niblet pipelines."""

import argparse
import sys
from pathlib import Path

from niblet import pipelines


def cmd_list(args) -> int:
    items = pipelines.list_pipelines(args.project_root)
    if not items:
        print("No pipelines found.")
        return 0
    print(f"{'name':<40} {'description'}")
    print("-" * 80)
    for item in items:
        desc = item["description"][:60]
        print(f"{item['name']:<40} {desc}")
    return 0


def cmd_show(args) -> int:
    p = pipelines.load_pipeline(args.project_root, args.name)
    if p is None:
        print(f"error: pipeline not found: {args.name}", file=sys.stderr)
        return 66
    print(f"# {p['name']}")
    if p["description"]:
        print(f"\n{p['description']}\n")
    print(p["body"])
    return 0


def cmd_run(args) -> int:
    p = pipelines.load_pipeline(args.project_root, args.name)
    if p is None:
        print(f"error: pipeline not found: {args.name}", file=sys.stderr)
        return 66

    print(f"# {p['name']}")
    print(p["body"])
    print("\n-- Run the steps above, then record the outcome. --")

    pipelines.record_usage(
        args.project_root,
        args.session_id,
        args.name,
        success=args.success,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-pipelines", description="List and run niblet pipelines")
    parser.add_argument("--project-root", required=True)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list", help="list available pipelines")
    p_list.set_defaults(func=cmd_list)

    p_show = sub.add_parser("show", help="show a pipeline")
    p_show.add_argument("--name", required=True)
    p_show.set_defaults(func=cmd_show)

    p_run = sub.add_parser("run", help="print a pipeline and record usage")
    p_run.add_argument("--name", required=True)
    p_run.add_argument("--session-id", required=True)
    p_run.add_argument("--success", type=lambda s: s.lower() == "true", default=True)
    p_run.set_defaults(func=cmd_run)

    args = parser.parse_args(argv)
    args.project_root = Path(args.project_root).resolve()
    if not args.project_root.is_dir():
        print(f"error: not a directory: {args.project_root}", file=sys.stderr)
        return 66

    return args.func(args)
