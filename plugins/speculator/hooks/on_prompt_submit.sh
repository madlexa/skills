#!/usr/bin/env bash
# on_prompt_submit.sh — fires on UserPromptSubmit.
#
# Runs the user's prompt through the speculator graph search and, if any
# entities/edges match, emits them as a system reminder so the agent has
# the relevant KB context before answering. This is the read side of the
# graph integration; writing to the KB stays an explicit agent action.
#
# Best-effort and non-blocking: every failure path (no node, no KB, empty
# prompt, CLI error, no matches) exits 0 without emitting anything.

set +e
set +u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"

# shellcheck source=../lib/paths.sh
. "$PLUGIN_ROOT/lib/paths.sh" 2>/dev/null || exit 0
# shellcheck source=../lib/graph.sh
. "$PLUGIN_ROOT/lib/graph.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null || true)"

CWD="$(speculator_cwd_from_stdin "$INPUT")"
PROMPT="$(speculator_field "$INPUT" prompt)"

# No prompt text -> nothing to search.
[ -n "$PROMPT" ] || exit 0

# Cap the query length before tokenizing so we never process megabytes.
PROMPT="$(printf '%s' "$PROMPT" | head -c 400)"

# Reduce the prompt to salient keywords: lowercase, split on non-alphanumeric,
# drop short tokens and common stopwords, dedupe, and cap the count. The search
# OR-matches these (see speculator_search --any), so a natural-language prompt
# surfaces entities mentioning any salient term — passing the raw sentence would
# require every word (incl. stopwords) to co-occur in one entity and match
# nothing.
KEYWORDS="$(printf '%s' "$PROMPT" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9' ' ' \
  | tr ' ' '\n' \
  | awk 'length($0) >= 3' \
  | grep -Ev '^(the|and|for|are|was|has|had|you|our|its|but|not|can|all|any|how|who|why|did|get|set|use|via|out|off|per|too|now|see|may|let|two|one|does|done|with|from|this|that|then|than|your|have|will|been|they|them|here|just|only|also|some|more|most|such|very|much|many|what|when|where|which|while|would|should|could|about|into|over|under|using|used|make|made|need|want|like|able|both|each|else|same|null|true|false)$' \
  | awk '!seen[$0]++' \
  | head -n 12 \
  | tr '\n' ' ')"

# Nothing meaningful left after filtering -> nothing to search.
[ -n "${KEYWORDS// /}" ] || exit 0

PROJECT_ROOT="$(speculator_project_root "$CWD")"
KB_DIR="$(speculator_kb_dir "$PROJECT_ROOT")"

# Bail quietly unless node, a populated KB, and the CLI are all present.
speculator_graph_ready "$PLUGIN_ROOT" "$KB_DIR" || exit 0

# Keywords are passed as a single argv to the search command — never eval'd,
# so shell metacharacters in them are inert.
MATCHES="$(speculator_search "$PLUGIN_ROOT" "$KB_DIR" "$KEYWORDS")"
rc=$?
[ "$rc" -eq 0 ] || exit 0
[ -n "$MATCHES" ] || exit 0

printf 'SPECULATOR graph matches for your prompt (read the entity files for detail):\n\n'
printf '%s\n' "$MATCHES" | head -n 40

exit 0
