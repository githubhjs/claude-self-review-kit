#!/bin/bash

# Copy to <your project>/.claude/verify.sh (or .chipagents/verify.sh) to turn
# on verify-gate. Exit 0 = checks pass and the agent may stop; non-zero = the
# agent is blocked and keeps fixing.
# It runs every time the agent tries to stop, so keep it fast (under a minute).

set -euo pipefail

# ---- Replace with your project's real checks (examples) ----
# make lint test
# python -m pytest -q
# npm test --silent
# verilator --lint-only -Wall rtl/top.v

# Until you edit it, guess from the project type:
if [[ -f package.json ]]; then
  npm test --silent
elif [[ -f pyproject.toml || -f pytest.ini || -f setup.cfg ]]; then
  python -m pytest -q
elif [[ -f Cargo.toml ]]; then
  cargo test --quiet
elif [[ -f go.mod ]]; then
  go test ./...
else
  echo "verify.sh: no test command detected; edit .claude/verify.sh and put in your checks." >&2
fi
