#!/bin/bash

# ralph-loop post_turn hook for ChipAgents (Claude Code uses stop-hook.sh).
# Port by Josh_HUANG; behaviour measured on ChipAgents 0.42.3 (2026-10-16).
# Differences forced by the ChipAgents hook API:
#   - stdin carries user_message (last-turn transcript TEXT), not
#     transcript_path / session_id, so there is no JSONL to walk and no session
#     isolation.
#   - a rerun requires a NON-ZERO EXIT. The documented
#     {"block": true, "message": "..."} form blocks the turn but never reruns
#     the agent.
#   - completion is signalled by WRITING A FILE, not by a tag in the reply.
#     ChipAgents feeds the previous hook's STDOUT back into the transcript, so
#     any tag this hook names in its own banner reappears in the next payload
#     and a transcript search would match itself.
#   - jq is not needed.
# Start a loop with scripts/setup-ralph-loop.sh; see the README.

set -uo pipefail

# Drain stdin: completion arrives as a file, so the transcript is not parsed.
cat > /dev/null

# Inner runs (a reviewer started by review-gate, chip-swarm investigators) load
# the same hooks; they are read-only and must not be looped.
[[ -z "${CHIPAGENTS_HOOKS_INNER:-}" ]] || exit 0

STATE=
for f in .chipagents/ralph-loop.local.md .claude/ralph-loop.local.md; do
  if [[ -f "$f" ]]; then
    STATE="$f"
    break
  fi
done

# No active loop: let the turn end, silently (this is the common case).
[[ -n "$STATE" ]] || exit 0

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE")
ITERATION=$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^iteration: *//p' | head -n 1)
MAX_ITERATIONS=$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^max_iterations: *//p' | head -n 1)
COMPLETION_PROMISE=$(printf '%s\n' "$FRONTMATTER" | sed -n 's/^completion_promise: *//p' | head -n 1 | sed 's/^"\(.*\)"$/\1/')

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "ralph-loop: $STATE is corrupted (iteration='$ITERATION' max_iterations='$MAX_ITERATIONS'). Stopping the loop." >&2
  rm -f "$STATE"
  exit 0
fi

# The promise file lives beside the state file, so the -nt comparison below is
# between two paths in the same directory and filesystem.
PROMISE="$(dirname "$STATE")/ralph-loop.promise"

# Completion is checked BEFORE max_iterations, so a genuine completion on the
# last allowed iteration is reported as completion, not exhaustion.
#
# Freshness: the state file is rewritten every iteration to bump the counter,
# so its mtime marks the start of the current round. A promise must be NEWER
# than the state file, so one left over from an earlier run or iteration cannot
# end a new loop.
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]] && [[ -f "$PROMISE" ]]; then
  if [[ "$PROMISE" -nt "$STATE" ]]; then
    PROMISE_TEXT=$(tr -s '[:space:]' ' ' < "$PROMISE" | sed 's/^ //; s/ $//')
    if [[ "$PROMISE_TEXT" == "$COMPLETION_PROMISE" ]]; then
      echo "ralph-loop: completion promise \"$COMPLETION_PROMISE\" received after iteration $ITERATION."
      rm -f "$STATE" "$PROMISE"
      exit 0
    fi
  fi
  # Stale or wrong text: discard it so a later iteration cannot count it.
  rm -f "$PROMISE"
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "ralph-loop: max iterations ($MAX_ITERATIONS) reached."
  rm -f "$STATE" "$PROMISE"
  exit 0
fi

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE")
if [[ -z "$PROMPT_TEXT" ]]; then
  echo "ralph-loop: $STATE has no prompt body. Stopping the loop." >&2
  rm -f "$STATE"
  exit 0
fi

NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${STATE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$STATE"

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Naming the promise here is safe: completion is read from a file, so this
  # banner coming back in the next transcript cannot satisfy the check.
  BANNER="Ralph iteration $NEXT_ITERATION. To end the loop, write the promise to its file:
  echo '$COMPLETION_PROMISE' > $PROMISE
Do that only when the task is completely and verifiably done. Writing it to
escape the loop while work remains is a false claim. Printing the phrase in
your reply has no effect; only the file counts, and it must be written during
this iteration."
else
  BANNER="Ralph iteration $NEXT_ITERATION. No completion promise is set; the loop ends only at max_iterations or when the post_turn_restarts budget runs out."
fi

# Report the block as an objective failure, i.e. a NON-ZERO EXIT. Measured
# 2026-10-16, do not "simplify" this back to JSON:
#   {"block": true, ...} with exit 0 -> blocked, but the agent is NEVER rerun
#   message on stdout with exit 1      -> the agent IS rerun and acts on it
# stdout is added to the agent's context.
printf '%s\n\n%s\n' "$BANNER" "$PROMPT_TEXT"
exit 1
