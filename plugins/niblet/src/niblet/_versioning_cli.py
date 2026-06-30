"""File-based versioning CLI."""

import argparse
import sys

from niblet import versioning


def cmd_save(args) -> int:
    vfile = versioning.save_version(args.action, args.name, args.scope, args.project_root)
    if vfile:
        print(f"saved: {vfile}")
    else:
        print("no-live-file: nothing to save")
    return 0


def cmd_list(args) -> int:
    versions = versioning.list_versions(args.action, args.name, args.project_root)
    if not versions:
        print("no-versions")
        return 0
    for v in versions:
        print(v)
    return 0


def cmd_restore(args) -> int:
    try:
        live = versioning.restore_version(args.action, args.name, args.ts, args.scope, args.project_root)
        print(f"restored: {live}")
        return 0
    except FileNotFoundError as e:
        print(f"error: {e}", file=sys.stderr)
        return 66


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="niblet-versioning", description="niblet file-based versioning")
    parser.add_argument("--project-root", required=True)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_save = sub.add_parser("save", help="save current live version")
    p_save.add_argument("--action", required=True)
    p_save.add_argument("--name", required=True)
    p_save.add_argument("--scope", default="project")
    p_save.set_defaults(func=cmd_save)

    p_list = sub.add_parser("list", help="list versions")
    p_list.add_argument("--action", required=True)
    p_list.add_argument("--name", required=True)
    p_list.set_defaults(func=cmd_list)

    p_restore = sub.add_parser("restore", help="restore a version")
    p_restore.add_argument("--action", required=True)
    p_restore.add_argument("--name", required=True)
    p_restore.add_argument("--ts", required=True)
    p_restore.add_argument("--scope", default="project")
    p_restore.set_defaults(func=cmd_restore)

    args = parser.parse_args(argv)
    return args.func(args)
