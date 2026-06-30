"""Restore an artifact version from .niblet/versions/."""

import argparse
import sys

from niblet import versioning


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-revert", description="Restore a niblet artifact version")
    parser.add_argument("--project-root", required=True, help="absolute project root")
    parser.add_argument("--action", required=True, help="action that produced the target artifact")
    parser.add_argument("--name", required=True, help="artifact name/slug")
    parser.add_argument("--ts", required=True, help="version timestamp, e.g. 20260629T123000Z")
    parser.add_argument("--scope", default="project", help="project or global")
    args = parser.parse_args(argv)

    try:
        live = versioning.restore_version(
            args.action, args.name, args.ts, args.scope, args.project_root
        )
        print(f"restored: {live}")
        return 0
    except FileNotFoundError as e:
        print(f"error: {e}", file=sys.stderr)
        return 66
