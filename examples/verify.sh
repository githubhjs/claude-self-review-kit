#!/bin/bash

# 複製到「你的專案」/.claude/verify.sh 就會啟用 verify-gate。
# exit 0 = 檢查通過，Claude 可以停；非 0 = Claude 會被擋下來繼續修。
# 每次 Claude 想結束都會跑一次，所以要盡量快（建議 < 1 分鐘）。

set -euo pipefail

# ---- 改成你專案真正的檢查（範例） ----
# make lint test
# python -m pytest -q
# npm test --silent
# verilator --lint-only -Wall rtl/top.v

# 沒改之前，先依專案類型自動猜：
if [[ -f package.json ]]; then
  npm test --silent
elif [[ -f pyproject.toml || -f pytest.ini || -f setup.cfg ]]; then
  python -m pytest -q
elif [[ -f Cargo.toml ]]; then
  cargo test --quiet
elif [[ -f go.mod ]]; then
  go test ./...
else
  echo "verify.sh: 沒有偵測到測試指令，請編輯 .claude/verify.sh 填入你的檢查。" >&2
fi
