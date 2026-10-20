# Claude Code 自我 Review ＋ 不停工套件

[English](README.md) | 繁體中文

讓 Claude Code **自己 review 自己的程式碼**，並且**在目標完成前不准停下來**。

這個資料夾是一個「本機 plugin marketplace」，可以直接安裝，不需要再連網路。

**也支援 ChipAgents**：verify-gate 和 ralph-loop 已經加上 ChipAgents 的 `hooks.toml` 版本，見第 13 節。

| Plugin | 作用 | 來源 |
|---|---|---|
| `ralph-loop` | **不要停**：Claude 想結束時被 Stop hook 擋下，把同一個任務再餵回去，直到它輸出完成暗號 | Anthropic 官方 |
| `verify-gate` | **用測試當關卡**：專案的 `.claude/verify.sh` 沒通過就不准停 | 本套件自製 |
| `pr-review-toolkit` | **自我 review**：6 個專職 reviewer agent，針對本機 `git diff` | Anthropic 官方（已修一個 bug） |
| `code-simplifier` | 寫完後把程式碼簡化、整理，不改變行為 | Anthropic 官方 |
| `code-review` | 對 **GitHub PR** 做多 agent review，並把結果留言回 PR | Anthropic 官方 |

---

## 1. 資料夾結構

```
claude-self-review-kit/
├── README.md                     ← 英文說明
├── README.zh-TW.md               ← 本說明（繁體中文）
├── .claude-plugin/marketplace.json  ← 本機 marketplace（名稱：self-review-kit）
├── plugins/
│   ├── ralph-loop/
│   ├── verify-gate/
│   ├── pr-review-toolkit/
│   ├── code-simplifier/
│   └── code-review/
├── examples/verify.sh            ← verify-gate 用的範本
└── chipagents-test/               ← ChipAgents 的 E2E 測試
```

## 2. 來源與版本

| 項目 | 版本 | 來源 |
|---|---|---|
| 4 個官方 plugin | commit `8f814f49002ff824e8a9ba43cf96112dc7f5948d`（2026-10-15） | https://github.com/anthropics/claude-plugins-official |

## 3. 需要的工具

- **jq**：Claude Code 版 ralph-loop 的 Stop hook 需要它。
  - 沒有 jq 時，hook 會以 `jq: command not found`（exit 127）失敗，**迴圈會無聲無息地不運作**。
  - Windows：`winget install jqlang.jq`。CentOS／RHEL：`dnf install jq`。
  - 裝完要完全關掉再重開 Claude Desktop 或終端機，新的 PATH 才會生效。
- **gh**（GitHub CLI）：只有 code-review plugin 需要。
  - Windows：`winget install GitHub.cli`。裝完自己執行一次 `gh auth login`。
- ChipAgents 版的 hook 只需要 bash，不需要 jq。

## 4. 安裝

```bash
claude plugin marketplace add githubhjs/claude-self-review-kit
```

或從本機 clone 安裝（路徑用正斜線，在 PowerShell 和 Git Bash 都可以用）：

```bash
claude plugin marketplace add /path/to/claude-self-review-kit
```

接著安裝需要的 plugin：

```bash
claude plugin install ralph-loop@self-review-kit
```

```bash
claude plugin install verify-gate@self-review-kit
```

```bash
claude plugin install pr-review-toolkit@self-review-kit
```

```bash
claude plugin install code-simplifier@self-review-kit
```

```bash
claude plugin install code-review@self-review-kit
```

裝完以後**重開 Claude Code**。可以用 `claude plugin list` 確認。

> 也可以改從線上官方來源安裝，例如 `claude plugin install ralph-loop@claude-plugins-official`。
> 但是官方的 `pr-review-toolkit` 目前有一個 agent 的 YAML 是壞的（見第 9 節），所以建議用本套件的版本。

---

## 5. ralph-loop：不要停

### 原理

1. 你下一次 `/ralph-loop "任務"`。
2. 系統寫入狀態檔 `.claude/ralph-loop.local.md`。
3. Claude 每次想結束時，Stop hook 會檢查最後一段輸出有沒有 `<promise>暗號</promise>`。
4. 沒有暗號 → 擋住，**把同一個任務再餵回去**，迭代次數 +1。
5. 有暗號，或達到 `--max-iterations` → 放行。

Claude 每一輪都看得到上一輪改過的檔案和 git 歷史，所以會在自己的成果上持續改進。

### 指令

| 指令 | 說明 |
|---|---|
| `/ralph-loop "任務" --completion-promise "COMPLETE" --max-iterations 20` | 開始迴圈 |
| `/cancel-ralph` | 中途取消（或直接刪除 `.claude/ralph-loop.local.md`） |
| `/ralph-loop --help` | 顯示說明 |

監看目前跑到第幾輪：

```bash
grep '^iteration:' .claude/ralph-loop.local.md
```

### 範例：一邊做、一邊自我 review

```
/ralph-loop "實作 <你的任務>。每一輪：1) 先看 git diff 和 NOTES.md 了解目前進度 2) 做下一步 3) 跑測試 4) 用 pr-review-toolkit 的 code-reviewer 和 silent-failure-hunter agent review 自己的 diff，修掉 Critical 和 Important 等級的問題 5) 把進度和還沒解決的問題寫進 NOTES.md。只有在測試全部通過、而且 review 沒有 Critical 或 Important 問題時，才輸出 <promise>COMPLETE</promise>" --completion-promise "COMPLETE" --max-iterations 20
```

### 注意事項

- **一定要設 `--max-iterations`**。不設的話會無限跑下去，token 也會一直燒。
- 暗號是**完全一致的字串比對**。請用不會誤觸的字串，例如 `COMPLETE`，不要用 `done`。
- 任務描述裡**不要放 `$` 或反引號 `` ` ``**，因為參數會經過 bash 解析。
- 狀態檔會綁定開啟迴圈的那個 session，同專案的其他 session 不受影響。
- 適合**有明確完成條件、而且能自動驗證**的任務（測試、lint、build）。不適合需要人做判斷或設計決策的任務。
- 建議把 `.claude/ralph-loop.local.md` 加進專案的 `.gitignore`。

---

## 6. verify-gate：用測試當關卡（本套件自製）

ralph-loop 是靠 Claude「自己說做完了」。verify-gate 則是用**客觀的檢查結果**來決定能不能停，兩個可以同時使用。

### 啟用（每個專案各自選擇要不要開）

把範本複製到**你的專案**底下：

```bash
cp /path/to/claude-self-review-kit/examples/verify.sh <你的專案>/.claude/verify.sh
```

然後編輯 `.claude/verify.sh`，填入真正的檢查，例如 `make lint test`、`python -m pytest -q`、`verilator --lint-only -Wall rtl/top.v`。

### 行為

| 情況 | 結果 |
|---|---|
| 專案沒有 `.claude/verify.sh`（也沒有 `.chipagents/verify.sh`） | 什麼都不做（不影響其他專案） |
| verify.sh 回傳 0 | 放行，Claude 可以結束 |
| verify.sh 回傳非 0 | **擋住**，並把最後 80 行錯誤訊息交給 Claude 繼續修 |
| 連續被擋超過 10 次 | 放行，避免修不好時無限迴圈（可用環境變數 `VERIFY_GATE_MAX_BLOCKS` 調整次數） |

- Claude **每一次**想結束時都會跑一次 verify.sh，所以檢查要快，建議 1 分鐘以內；hook 的上限是 10 分鐘。
- 擋住時的訊息會明確要求 Claude **不准修改或放寬 verify.sh 和測試**來作弊。
- 要暫時關閉：把 `.claude/verify.sh` 改名。要整個停用：`claude plugin disable verify-gate@self-review-kit`。
- 建議把 `.claude/verify-gate.count` 加進 `.gitignore`。

---

## 7. 自我 review 工具

### pr-review-toolkit（最適合自我 review）

針對**本機的 `git diff`**，不需要 GitHub。

```
/pr-review-toolkit:review-pr                # 全部面向
/pr-review-toolkit:review-pr code errors    # 只看一般品質＋錯誤處理
/pr-review-toolkit:review-pr all parallel   # 全部 agent 平行跑（較快、較耗 token）
```

| Agent | 檢查重點 |
|---|---|
| `code-reviewer` | 是否符合 CLAUDE.md 規範、bug、一般程式品質 |
| `silent-failure-hunter` | 被吞掉的錯誤、空的 catch、不當的 fallback |
| `pr-test-analyzer` | 測試覆蓋率和測試品質 |
| `comment-analyzer` | 註解是否正確、是否已經過時 |
| `type-design-analyzer` | 型別設計、封裝、不變式 |
| `code-simplifier` | review 通過後做精簡 |

輸出會分成 Critical、Important、Suggestions 三個等級，並附上 `file:line`。

### code-simplifier

一個 agent，會把最近修改過的程式碼整理得更清楚，但不改變行為。直接請 Claude「用 code-simplifier 整理剛剛的修改」即可。

### code-review（GitHub PR 專用）

```
/code-review:code-review
```

- 會讀 GitHub PR，平行跑 5 個 reviewer，再用信心分數過濾，只保留 80 分以上的問題。
- **最後會用 `gh` 把結果直接留言到 PR 上，是公開的、對外的動作。**
- 需要 GitHub，並且要先自己執行一次 `gh auth login` 登入。
- 你的 Claude Code 也內建一個同名的 `/code-review`（review 目前的 diff，加 `--fix` 會直接修改）。為了避免混淆，plugin 版請用完整名稱 `/code-review:code-review`。

### 內建、不用安裝的工具

- `/code-review`：review 目前的 diff，可加 `--fix`
- `/simplify`：只做程式碼品質上的清理

---

## 8. 推薦組合

1. 在專案放好 `.claude/verify.sh`（verify-gate）→ **測試沒過不准停**
2. 用 `/ralph-loop` 下任務，prompt 裡要求每一輪都要做 review（見第 5 節範例）→ **做完一輪接著做下一輪**
3. 結束前跑一次 `/pr-review-toolkit:review-pr all` → **最後一道人工檢查前的總體檢**

---

## 9. 本套件相對官方原版的修改

用 `diff -r` 和 Claude Code 自己下載的官方版本比對過，**只有以下差異**：

1. **修正 `pr-review-toolkit/agents/silent-failure-hunter.md`**：
   - 原版 `description:` 沒有加引號，內容又含有 `: `，導致 YAML 解析失敗。
   - 後果是這個 agent 載入時名稱和描述都是空的。`claude plugin validate` 會回報 `✘ Validation failed`。
   - 修法：把 description 用雙引號包起來，內文不變。修完後 validate 通過。
2. 所有文字檔都統一成 **LF 換行**。
   - Git for Windows 預設 `core.autocrlf=true`，手動 `git clone` 時 `.sh` 會變成 CRLF，bash 就無法執行。
   - 另外加了 `.gitattributes`，確保 `.sh` 一律維持 LF。
3. 新增 `verify-gate` plugin、`examples/verify.sh`。
4. 為 ChipAgents 新增以下檔案，Claude Code 會忽略它們（見第 13 節）：
   - `ralph-loop` 和 `verify-gate` 各多一個 `.chipagents-plugin/plugin.json`、`hooks/hooks.toml`
   - `ralph-loop/hooks/post-turn-ralph.sh`
   - `chipagents-test/`
5. `code-simplifier`（以及 pr-review-toolkit 裡的 code-simplifier agent）在原本的 TypeScript 規範之外，加入 SystemVerilog/RTL 規範，並把「保留功能」在 RTL 的意義定義為 cycle-accurate 等價。

## 10. 疑難排解

| 症狀 | 原因與解法 |
|---|---|
| ralph-loop 沒有繼續跑下一輪 | 多半是找不到 jq。重開 Claude Desktop 讓新的 PATH 生效，再用 `jq --version` 確認 |
| `wsl: Unknown key ...` 或 `execvpe(/bin/bash) failed` | `bash` 被解析成 WSL 的 bash（Windows 的 PowerShell 裡，`bash` 常常指向 `WindowsApps\bash.exe`）。把該 plugin 的 `hooks/hooks.json` 裡的 `bash` 改成 `"C:/Program Files/Git/bin/bash.exe"` |
| `$'\r': command not found` | `.sh` 變成了 CRLF。執行 `sed -i 's/\r$//' 檔名.sh` |
| plugin 指令沒出現 | 安裝後要重開 Claude Code。用 `claude plugin list` 確認 |
| code-review 失敗 | 還沒執行 `gh auth login`，或專案不在 GitHub 上 |

## 11. 解除安裝

```bash
claude plugin uninstall ralph-loop@self-review-kit
```

```bash
claude plugin marketplace remove self-review-kit
```

## 12. 授權

- 官方 plugin：Apache License 2.0（見各 plugin 目錄內的 `LICENSE`）
- verify-gate、chipagents-test 和本套件其他部分：MIT（`LICENSE`）

---

## 13. 在 ChipAgents 使用

ChipAgents 可以用 `--type claude` 安裝 Claude Code 格式的 marketplace。不過它**不支援 Claude 的 `hooks/hooks.json`**，hook 改用自己的 `hooks.toml`。

### 相容性

| Plugin | 在 ChipAgents | 說明 |
|---|---|---|
| `verify-gate` | ✅ 已移植 | 改用 `post_turn` hook 加上 `blocking = true`、`enable_restarts = true`：檢查失敗時，ChipAgents 會帶著錯誤訊息讓 agent 重跑 |
| `ralph-loop` | ✅ 已移植，但用法不同 | 用終端機啟動，用檔案通知完成（見下方） |
| `pr-review-toolkit` | ✅ 可用 | agents 和 commands 都支援。`model`、`color`、`allowed-tools` 這些 Claude 專用欄位可能會被忽略 |
| `code-simplifier` | ✅ 可用 | 除了原本的 JS/TS 規範，已加入 SystemVerilog/RTL 規範 |
| `code-review` | ⚠️ 可載入 | 只能用在 GitHub PR，需要 `gh` |

Claude Code 內建的 `/code-review`、`/simplify`、`/loop` 不是 plugin，ChipAgents 沒有這些功能。

### 安裝（在 CentOS 上）

```bash
chipagents plugin marketplace add githubhjs/claude-self-review-kit --type claude
chipagents plugin install verify-gate@self-review-kit
chipagents plugin install ralph-loop@self-review-kit
chipagents plugin install pr-review-toolkit@self-review-kit
```

如果是在 session 裡安裝，裝完執行 `/reload`。

### verify-gate（ChipAgents 版）

- 在專案放 `.chipagents/verify.sh`。`.claude/verify.sh` 也可以，兩者同時存在時優先使用 `.claude/verify.sh`，所以同一份檢查腳本兩邊共用。
- 每個 agent turn 結束後會跑一次。失敗時（exit 非 0），ChipAgents 會把最後 80 行錯誤訊息交給 agent，讓它**重跑並修正**。
- 重跑次數 = `post_turn_restarts` − 1（實測）。plugin 設的是 11，但 `~/.chipagents` 或 workspace 裡的值會優先，所以請在 workspace 的 `.chipagents/hooks.toml` 設定額度。連續 10 次的保護上限仍然有效。
- 單次檢查最長 600 秒。
- RTL 專案的 verify.sh 可以放 `slang`、`verilator --lint-only` 或小型 regression。ChipAgents 也有內建的 `slang` hook 型別可以搭配使用。

### ralph-loop（ChipAgents 版）

ChipAgents 的 hook 只拿得到「上一輪的 transcript 文字」，裡面可能包含你自己的 prompt。如果 prompt 裡寫了 `<promise>` 標籤，迴圈會被誤判成已完成，所以 **ChipAgents 版改用檔案通知完成**。

1. 在專案目錄的終端機啟動迴圈，**不要用 `/ralph-loop` 指令**，那是給 Claude Code 用的：

   ```bash
   bash /path/to/claude-self-review-kit/plugins/ralph-loop/scripts/setup-ralph-loop.sh "讓 uart_tb 全部通過" --completion-promise COMPLETE --max-iterations 10
   ```

2. 在 ChipAgents 下同一個任務，並在 prompt 加上一句：「完全做完時執行 `echo COMPLETE > .claude/ralph-loop.promise`」。
3. 每一輪結束，hook 會檢查 `.claude/ralph-loop.promise`：
   - 檔案內容正確，而且是這一輪才寫的 → 迴圈結束。
   - 沒有這個檔案、內容不對，或是之前留下的舊檔 → 把同一個任務再交給 agent 重跑。
4. 要取消，刪掉狀態檔：

   ```bash
   rm .claude/ralph-loop.local.md
   ```

- 重跑次數 = `post_turn_restarts` − 1（實測），所以要在 **workspace** 的 `.chipagents/hooks.toml` 把 `post_turn_restarts` 設成至少 `--max-iterations` + 1。plugin 自己的值（21）會被 `~/.chipagents` 或 workspace 裡的值蓋掉。
- 狀態檔也可以放在 `.chipagents/ralph-loop.local.md`，promise 檔一律放在它旁邊。在回覆裡印出暗號沒有用，因為 ChipAgents 會把 hook 的 stdout 餵回 transcript；只有寫檔才算數。
- 這個 hook 只需要 bash，不需要 jq。

### 注意事項

- **`post_turn_restarts` 以最先讀到的值為準**，`~/.chipagents` 或 workspace 裡的值會蓋掉 plugin 的值。重跑次數 = 這個值 − 1。
- **安裝時要用和跑 session 相同版本的 ChipAgents。** `PATH` 上排在前面的若是較舊的 `chipagents`（0.20.2，而 session 跑的是 0.42.3），裝出來的 `installed.json` 沒有 `hooks` 欄位，hook 完全不會執行。
- `chipagents plugin install` 對已安裝的 plugin 不會有任何動作；更新後要執行 `chipagents plugin update <plugin>@self-review-kit`。
- ChipAgents hook 行為的實測結果整理在 [chipagents-loop-kit/docs/chipagents-hook-mechanics.md](https://github.com/githubhjs/chipagents-loop-kit/blob/main/docs/chipagents-hook-mechanics.md)（英文）。
- **Preserved thinking 模型**（管理員設定了 `thinkingRequiresIdenticalPrefix`）：ChipAgents 文件提醒，`post_turn` 的 restart 可能讓之前的 thinking blocks 被丟掉。用這類模型時先小規模試用。
- **shell**：ChipAgents 用 `$SHELL` 執行 hook。在 EDA 環境常見的 tcsh 下，指令只是 `bash "<路徑>"`，可以正常執行。
- **E2E Mode 不是自動迴圈**。它是 ChipAgents CLI 的測試工具，每個測試上限是 50 個動作、10 分鐘。適合拿來驗證上面的設定有沒有生效。

### 驗證 ChipAgents 版的 verify-gate（E2E 測試）

這些移植使用的重跑機制（stdout + exit 1）和 ralph-loop 的 promise 檔，**已由 Josh_HUANG 在 ChipAgents 0.42.3 的 batch 模式實測過**；互動模式還沒實測。可以用下面的 E2E 測試驗證你的環境。

```bash
mkdir /tmp/vg-test && cd /tmp/vg-test && git init -q && mkdir .chipagents
cp /path/to/claude-self-review-kit/chipagents-test/verify.sh .chipagents/verify.sh
chipagents validate ~/.chipagents          # 或檢查 plugin 的 hooks.toml
chipagents e2e-mode /path/to/claude-self-review-kit/chipagents-test/e2e-verify-gate.json
```

測試的設計：
- 要求 agent 寫入 `status: draft`，但 verify.sh 要求檔案內容必須是 `status: ready`。
- **只有 hook 真的讓 agent 重跑並改正，測試才會通過**。
- 報告會寫在 `e2e-mode-run-*.log`。

如果想看 hook 實際收到什麼輸入，可以在專案的 `.chipagents/hooks.toml` 暫時加入下面這段，跑一次後看 `/tmp/post-turn.json`：

```toml
[[post_turn]]
type = "bash"
command = "cat > /tmp/post-turn.json"
```

## 作者

Chih-Hsueh "Josh" HUANG
