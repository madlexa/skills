"""Unified CLI entry point for niblet Python tools."""

import argparse
import sys

from niblet._capture_read import main as capture_read_main
from niblet._capture_task import main as capture_task_main
from niblet._metrics_cli import main as metrics_main
from niblet._pipelines_cli import main as pipelines_main
from niblet._ratchet import main as ratchet_main
from niblet._revert import main as revert_main
from niblet._versioning_cli import main as versioning_main


# Each subcommand module exposes a main(argv=None) function.
COMMANDS = {
    "capture-read": capture_read_main,
    "capture-task": capture_task_main,
    "metrics": metrics_main,
    "pipelines": pipelines_main,
    "versioning": versioning_main,
    "ratchet": ratchet_main,
    "revert": revert_main,
}


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    parser = argparse.ArgumentParser(
        prog="python3 -m niblet",
        description="Unified niblet CLI.",
    )
    parser.add_argument(
        "command",
        choices=list(COMMANDS.keys()),
        help="Subcommand to run",
    )
    parser.add_argument(
        "args",
        nargs=argparse.REMAINDER,
        help="Arguments forwarded to the subcommand",
    )

    args = parser.parse_args(argv)
    # argparse.REMAINDER may leave a leading '--' if the user used it.
    if args.args and args.args[0] == "--":
        args.args = args.args[1:]

    return COMMANDS[args.command](args.args)


if __name__ == "__main__":
    sys.exit(main())
