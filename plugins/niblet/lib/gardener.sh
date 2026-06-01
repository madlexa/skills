#!/usr/bin/env bash
# gardener.sh — shared helpers for niblet-skill-gardener.

# Extract a top-level envelope field from a proposal file.
# Usage: niblet_proposal_key <file> <key>
niblet_proposal_key() {
  local file="$1" key="$2"
  awk -v K="$key" '
    FNR == 1 { c = 0 }
    /^---$/ { c++; next }
    c == 1 {
      if (match($0, "^" K "[[:space:]]*:[[:space:]]*")) {
        v = substr($0, RLENGTH + 1)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
    c >= 2 { exit }
  ' "$file"
}

# Return 0 if the proposal carries a rejected_reason field (any value).
niblet_proposal_has_rejection() {
  local file="$1"
  awk '
    FNR == 1 { c = 0 }
    /^---$/ { c++; next }
    c == 1 {
      if (match($0, "^rejected_reason[[:space:]]*:")) { found = 1; exit }
    }
    c >= 2 { exit }
    END { exit !found }
  ' "$file" 2>/dev/null
}

# Return 0 if the proposal is eligible for auto-promotion.
# Usage: niblet_proposal_can_autopromote <file>
niblet_proposal_can_autopromote() {
  local file="$1"
  local action scope risk confidence

  action="$(niblet_proposal_key "$file" action)"
  scope="$(niblet_proposal_key "$file" scope)"
  risk="$(niblet_proposal_key "$file" risk)"
  confidence="$(niblet_proposal_key "$file" confidence)"

  [ "$scope" = "project" ] || return 1
  [ "$risk" = "low" ]      || return 1
  [ "$confidence" = "high" ] || return 1
  niblet_proposal_has_rejection "$file" && return 1

  case "$action" in
    CREATE_SKILL|UPDATE_SKILL|MERGE_SKILL|UPDATE_AGENT|MERGE_AGENT|UPDATE_COMMAND|UPDATE_SCRIPT|UPDATE_CLAUDE|UPDATE_AGENTS|MERGE_KB_ENTRY|UPDATE_KB_ENTRY)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Return a one-word reason why a proposal is not eligible.
# Usage: niblet_proposal_skip_reason <file>
niblet_proposal_skip_reason() {
  local file="$1"
  local action scope risk confidence

  action="$(niblet_proposal_key "$file" action)"
  scope="$(niblet_proposal_key "$file" scope)"
  risk="$(niblet_proposal_key "$file" risk)"
  confidence="$(niblet_proposal_key "$file" confidence)"

  if niblet_proposal_has_rejection "$file"; then
    echo "rejected"
    return
  fi
  [ "$scope" = "project" ]   || { echo "global-scope"; return; }
  [ "$risk" = "low" ]        || { echo "risk=$risk"; return; }
  [ "$confidence" = "high" ] || { echo "confidence=$confidence"; return; }
  case "$action" in
    CREATE_SKILL|UPDATE_SKILL|MERGE_SKILL|UPDATE_AGENT|MERGE_AGENT|UPDATE_COMMAND|UPDATE_SCRIPT|UPDATE_CLAUDE|UPDATE_AGENTS|MERGE_KB_ENTRY|UPDATE_KB_ENTRY)
      echo "eligible"
      ;;
    *)
      echo "action=$action"
      ;;
  esac
}
