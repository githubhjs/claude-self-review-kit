#!/bin/bash

# Ralph Loop post_turn hook for ChipAgents (Claude Code uses stop-hook.sh).
#
# ChipAgents reruns the agent when a blocking post_turn hook exits non-zero.
# Its hook input carries only transcript text, which can contain the user's
# own prompt, so completion is signalled with a file instead of a
# <promise> tag: the agent writes the promise phrase to
# .claude/ralph-loop.promise. Only a promise file written after the current
# iteration began counts, so a stale one cannot end a new loop.
# Start a loop with scripts/setup-ralph-loop.sh. Needs only bash.

set -uo pipefail

# Drain the hook input; this hook does not need it.
cat > /dev/null

RALPH_STATE_FILE=".claude/ralph-loop.local.md"
PROMISE_FILE=".claude/ralph-loop.promise"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Ralph loop: state file $RALPH_STATE_FILE is corrupted; stopping. Run setup-ralph-loop.sh again to start fresh."
  rm -f "$RALPH_STATE_FILE" "$PROMISE_FILE"
  exit 0
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]] && [[ -f "$PROMISE_FILE" ]]; then
  if [[ "$PROMISE_FILE" -nt "$RALPH_STATE_FILE" ]]; then
    PROMISE_TEXT=$(tr -s '[:space:]' ' ' < "$PROMISE_FILE" | sed 's/^ //; s/ $//')
    if [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
      echo "Ralph loop: completion promise \"$COMPLETION_PROMISE\" received after iteration $ITERATION."
      rm -f "$RALPH_STATE_FILE" "$PROMISE_FILE"
      exit 0
    fi
  fi
  # Stale or wrong promise: discard it so it cannot count later.
  rm -f "$PROMISE_FILE"
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Ralph loop: max iterations ($MAX_ITERATIONS) reached."
  rm -f "$RALPH_STATE_FILE" "$PROMISE_FILE"
  exit 0
fi

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")
if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Ralph loop: no prompt found in $RALPH_STATE_FILE; stopping."
  rm -f "$RALPH_STATE_FILE" "$PROMISE_FILE"
  exit 0
fi

NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# Non-zero exit makes ChipAgents rerun the agent with this output.
echo "Ralph loop iteration $NEXT_ITERATION. Continue working on the same task:"
echo
echo "$PROMPT_TEXT"
echo
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  echo "When, and only when, the task is completely and verifiably done, run:"
  echo "  echo '$COMPLETION_PROMISE' > $PROMISE_FILE"
  echo "Do not write it to escape the loop if you are stuck; the loop must end only when this is genuinely true."
fi
exit 1
