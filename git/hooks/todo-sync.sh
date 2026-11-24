#!/usr/bin/env bash
# Owns the "a branch was finished, its TODOs need reconciling" marker file.
#
# Split of responsibility: the post-checkout git hook has the right *trigger*
# (it sees every branch switch, including ones you make in a plain terminal)
# but no way to reason about TODOs. Claude has the reasoning but never sees
# your terminal. So the hook records here, and a Claude SessionStart hook
# reads here — this script is the only thing that knows the file format.
#
# Usage:
#   todo-sync.sh record <repo-dir> <left-branch> <entered-branch>
#   todo-sync.sh read                 # human-readable, empty if nothing pending
#   todo-sync.sh claude-context       # SessionStart hook JSON on stdout
#   todo-sync.sh clear [repo-dir [branch]]   # no args clears everything
#
# Not named after a git hook event, so git ignores it even though it sits in
# the hooksPath directory — see install-hooks.sh.

set -uo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/git-todo-sync"
PENDING="$STATE_DIR/pending"
TAB=$'\t'

usage() {
    echo "usage: $(basename "$0") {record <repo> <left> <entered>|read|claude-context|clear [repo [branch]]}" >&2
    exit 2
}

cmd_record() {
    repo=$1 left=$2 entered=$3
    [ -n "$repo" ] && [ -n "$left" ] || return 0

    mkdir -p "$STATE_DIR" || return 0

    # Already pending for this repo+branch — don't duplicate.
    if [ -f "$PENDING" ] && grep -qF "$repo$TAB$left$TAB" "$PENDING" 2>/dev/null; then
        return 0
    fi

    printf '%s\t%s\t%s\t%s\n' \
        "$repo" "$left" "$entered" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PENDING"
}

# One "  · repo: left → entered (date)" line per pending entry.
format_pending() {
    [ -s "$PENDING" ] || return 1
    awk -F'\t' 'NF>=3 {printf "  · %s: finished %s (now on %s, recorded %s)\n", $1, $2, $3, $4}' "$PENDING"
}

cmd_read() {
    format_pending || return 0
}

cmd_claude_context() {
    body=$(format_pending) || { echo '{}'; return 0; }
    [ -n "$body" ] || { echo '{}'; return 0; }

    context="Pending TODO sync — these branches were finished and left since the last sync:

$body
Reconcile each one's TODOs with the task list, then clear the marker with:
  ${BASH_SOURCE[0]:-$0} clear <repo-dir> <branch>
Only do this if the user asks about tasks/TODOs/status, or after finishing
their current request — don't derail whatever they opened this session for."

    if command -v jq >/dev/null 2>&1; then
        jq -n --arg ctx "$context" \
            '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
    else
        # No jq: hand-encode. Backslashes first, then quotes, then newlines.
        escaped=${context//\\/\\\\}
        escaped=${escaped//\"/\\\"}
        escaped=${escaped//$'\n'/\\n}
        printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
    fi
}

cmd_clear() {
    repo=${1:-} branch=${2:-}
    [ -f "$PENDING" ] || return 0

    if [ -z "$repo" ]; then
        rm -f "$PENDING"
        return 0
    fi

    tmp=$(mktemp) || return 1
    if [ -n "$branch" ]; then
        grep -vF "$repo$TAB$branch$TAB" "$PENDING" > "$tmp" 2>/dev/null
    else
        grep -vF "$repo$TAB" "$PENDING" > "$tmp" 2>/dev/null
    fi
    mv "$tmp" "$PENDING"
    [ -s "$PENDING" ] || rm -f "$PENDING"
}

case "${1:-}" in
    record)         shift; cmd_record "${1:-}" "${2:-}" "${3:-}" ;;
    read)           cmd_read ;;
    claude-context) cmd_claude_context ;;
    clear)          shift; cmd_clear "${1:-}" "${2:-}" ;;
    *)              usage ;;
esac
