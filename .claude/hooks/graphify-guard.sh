#!/bin/sh
# PreToolUse hook: point sessions at the graphify knowledge graph before they grep raw source.
#
# Wired up in .claude/settings.json for Bash|Grep (mode "search") and Glob (mode "read").
# `Read` was in the second matcher and was dropped: it fires on every targeted read during a
# focused edit, where the graph has already done its job. Add it back if discovery matters more
# than quiet.
#
# Three properties this script exists to guarantee, none of which a bare `graphify hook-guard`
# call in settings.json can provide:
#
#   1. PORTABLE. `graphify` is installed per-user and is usually NOT on PATH, so settings.json
#      cannot just say `graphify`. Hardcoding one absolute path breaks every other machine —
#      including the Windows box in CLAUDE.md, which has no graphify at all. This resolves
#      through PATH first, then the known per-user install locations.
#
#   2. FAIL-OPEN. This runs in front of every Bash/Grep/Read/Glob call in the repo. If graphify
#      is missing, broken, or slow, that must be a silent no-op — never a blocked tool call.
#      Every exit path here is 0, and stderr is discarded.
#
#   3. SELF-BOOTSTRAPPING. graphify-out/ is gitignored (graph.json is ~11 MB and rewrites
#      wholesale on every refresh), so a fresh clone has no graph. `graphify hook-guard` is
#      silent in that state, which would mean sessions on a new clone are never told the graph
#      exists at all. So when graphify is installed but the graph is missing, emit our own nudge
#      to generate it. That is a one-command fix, and once generated hook-guard takes over.
#
# Usage: graphify-guard.sh <search|read>

MODE="${1:-search}"

ROOT="${CLAUDE_PROJECT_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}"

# 1. Resolve the binary. PATH wins; then the standard per-user install locations.
GRAPHIFY="$(command -v graphify 2>/dev/null)"
if [ -z "$GRAPHIFY" ]; then
    for candidate in \
        "$HOME/.local/bin/graphify" \
        "$HOME/.local/share/uv/tools/graphifyy/bin/graphify"
    do
        if [ -x "$candidate" ]; then
            GRAPHIFY="$candidate"
            break
        fi
    done
fi

# Not installed — stay completely silent. This is the Windows-machine path.
[ -n "$GRAPHIFY" ] || exit 0

# 2. No graph yet: tell the session how to build one, rather than saying nothing.
if [ ! -f "$ROOT/graphify-out/graph.json" ]; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"This repo uses a graphify knowledge graph for code navigation, but graphify-out/graph.json is missing (it is gitignored — regenerable, not committed). Run `graphify update .` from the repo root once (a few seconds, AST-only, no API cost), then prefer `graphify query \"<question>\"` over raw grep for codebase questions. If that command fails, ignore this and continue normally."}}'
    exit 0
fi

# 3. Normal path — let graphify speak for itself. Never let its failure block the tool call.
"$GRAPHIFY" hook-guard "$MODE" 2>/dev/null || true
exit 0
