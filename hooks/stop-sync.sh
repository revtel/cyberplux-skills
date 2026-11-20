#!/usr/bin/env bash
# Claude Code Stop hook: when the agent finishes a turn in a repository that has
# a .cyberplux file and its lockfiles changed since the last upload, regenerate
# the SBOM and upload it. Silent when nothing changed or the repo is not opted in.
# Never blocks the agent: failures are reported as a message, exit code is 0.
input=$(cat)
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.cyberplux" ] || exit 0

script="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/skills/cyberplux-sbom-sync/scripts/cyberplux-sbom"
out=$("$script" sync --if-changed --quiet 2>&1); status=$?
[ -n "$out" ] || exit 0
[ $status -eq 0 ] || out="CyberPlux SBOM sync failed: $out"
# JSON-escape the message for systemMessage.
msg=$(printf '%s' "$out" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//')
printf '{"systemMessage":"%s"}\n' "$msg"
exit 0
