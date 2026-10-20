#!/bin/bash

# Test-only verify script for e2e-verify-gate.json: passes only when
# handoff.txt contains the line "status: ready".
if grep -qx 'status: ready' handoff.txt 2>/dev/null; then
  exit 0
fi
echo "handoff.txt must contain exactly the line: status: ready"
exit 1
