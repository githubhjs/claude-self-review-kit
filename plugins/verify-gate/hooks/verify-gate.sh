#!/bin/bash

# verify-gate hook for Claude Code (Stop) and ChipAgents (post_turn)
# Keeps the agent working while the project's verify script fails:
# .claude/verify.sh or .chipagents/verify.sh, whichever exists first.
# Projects without either script are unaffected. Needs only bash (no jq).

set -uo pipefail

# Drain the hook input; this hook does not need it.
cat > /dev/null

VERIFY_SCRIPT=
for candidate in .claude/verify.sh .chipagents/verify.sh; do
  if [[ -f "$candidate" ]]; then
    VERIFY_SCRIPT="$candidate"
    break
  fi
done
if [[ -z "$VERIFY_SCRIPT" ]]; then
  exit 0
fi

COUNT_FILE="$(dirname "$VERIFY_SCRIPT")/verify-gate.count"
MAX_BLOCKS="${VERIFY_GATE_MAX_BLOCKS:-10}"

OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
STATUS=$?

if [[ $STATUS -eq 0 ]]; then
  rm -f "$COUNT_FILE"
  exit 0
fi

# Cap consecutive blocks so a failure the agent cannot fix does not loop forever.
PREVIOUS=$(cat "$COUNT_FILE" 2>/dev/null || true)
[[ "$PREVIOUS" =~ ^[0-9]+$ ]] || PREVIOUS=0
COUNT=$((PREVIOUS + 1))

if [[ $COUNT -gt $MAX_BLOCKS ]]; then
  rm -f "$COUNT_FILE"
  echo "verify-gate: $VERIFY_SCRIPT still failing after $MAX_BLOCKS attempts; letting the agent stop." >&2
  exit 0
fi

echo "$COUNT" > "$COUNT_FILE"

# Claude Code feeds stderr of an exit-2 Stop hook back to the model.
# ChipAgents reruns the agent on any non-zero exit of a blocking post_turn
# hook and reports the hook's output, so write there instead.
if [[ -n "${CHIPAGENTS_PLUGIN_ROOT:-}" ]]; then
  exec 3>&1
else
  exec 3>&2
fi
{
  echo "verify-gate ($COUNT/$MAX_BLOCKS): $VERIFY_SCRIPT failed with exit code $STATUS."
  echo "Fix the failures below before finishing. Do not edit, skip or weaken $VERIFY_SCRIPT or the tests it runs to make it pass."
  echo "----- last 80 lines of output -----"
  echo "$OUTPUT" | tail -n 80
} >&3
exit 2
