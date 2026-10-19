# Claude Code self-review + keep-going kit

English | [繁體中文](README.zh-TW.md)

Make Claude Code **review its own code** and **not stop until the goal is
done**.

This repository is a Claude Code plugin marketplace you can install directly.

**ChipAgents is supported too**: verify-gate and ralph-loop ship ChipAgents
`hooks.toml` versions. See [section 13](#13-using-it-with-chipagents).

| Plugin | What it does | Source |
|---|---|---|
| `ralph-loop` | **Keep going**: when Claude tries to stop, a Stop hook blocks it and feeds the same task back until Claude outputs the completion phrase | Anthropic (official) |
| `verify-gate` | **Tests as the gate**: Claude may not stop while the project's `.claude/verify.sh` fails | This kit |
| `pr-review-toolkit` | **Self-review**: 6 specialised reviewer agents for your local `git diff` | Anthropic (official, one bug fixed) |
| `code-simplifier` | Simplifies and tidies freshly written code without changing behaviour | Anthropic (official) |
| `code-review` | Multi-agent review of a **GitHub PR** that posts its result as a PR comment | Anthropic (official) |

---

## 1. Layout

```
claude-self-review-kit/
├── README.md                        ← this file
├── .claude-plugin/marketplace.json  ← marketplace (name: self-review-kit)
├── plugins/
│   ├── ralph-loop/
│   ├── verify-gate/
│   ├── pr-review-toolkit/
│   ├── code-simplifier/
│   └── code-review/
├── examples/verify.sh               ← template for verify-gate
└── chipagents-test/                 ← ChipAgents E2E test
```

## 2. Sources and versions

| Item | Version | Source |
|---|---|---|
| 4 official plugins | commit `8f814f49002ff824e8a9ba43cf96112dc7f5948d` (2026-10-15) | https://github.com/anthropics/claude-plugins-official |

## 3. Required tools

- **jq**: needed by the Claude Code version of ralph-loop's Stop hook.
  - Without jq the hook fails with `jq: command not found` (exit 127), and
    **the loop silently does nothing**.
  - Windows: `winget install jqlang.jq`. CentOS/RHEL: `dnf install jq`.
  - After installing, fully quit and reopen Claude Desktop or your terminal so
    the new PATH takes effect.
- **gh** (GitHub CLI): only the code-review plugin needs it.
  - Windows: `winget install GitHub.cli`, then run `gh auth login` yourself once.
- The ChipAgents hooks need only bash, not jq.

## 4. Install

```bash
claude plugin marketplace add githubhjs/claude-self-review-kit
```

Or, from a local clone (forward slashes work in both PowerShell and Git Bash):

```bash
claude plugin marketplace add /path/to/claude-self-review-kit
```

Then install the plugins you want:

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

**Restart Claude Code** afterwards and check with `claude plugin list`.

> You can also install from the official marketplace, for example
> `claude plugin install ralph-loop@claude-plugins-official`. However, the
> official `pr-review-toolkit` currently has one agent with broken YAML (see
> section 9), so this kit's copy is recommended.

---

## 5. ralph-loop: keep going

### How it works

1. You run `/ralph-loop "task"` once.
2. It writes the state file `.claude/ralph-loop.local.md`.
3. Whenever Claude tries to stop, the Stop hook checks Claude's last output for
   `<promise>PHRASE</promise>`.
4. No phrase → the stop is blocked and **the same task is fed back**; the
   iteration count goes up by one.
5. Phrase found, or `--max-iterations` reached → Claude may stop.

Each iteration sees the files and git history the previous ones changed, so
Claude keeps improving on its own work.

### Commands

| Command | Purpose |
|---|---|
| `/ralph-loop "task" --completion-promise "COMPLETE" --max-iterations 20` | Start a loop |
| `/cancel-ralph` | Cancel it (or delete `.claude/ralph-loop.local.md`) |
| `/ralph-loop --help` | Show help |

See which iteration it is on:

```bash
grep '^iteration:' .claude/ralph-loop.local.md
```

### Example: work and self-review every iteration

```
/ralph-loop "Implement <your task>. Every iteration: 1) read git diff and NOTES.md to see where things stand 2) do the next step 3) run the tests 4) review your own diff with pr-review-toolkit's code-reviewer and silent-failure-hunter agents and fix every Critical and Important issue 5) write progress and open problems to NOTES.md. Output <promise>COMPLETE</promise> only when all tests pass and the review has no Critical or Important issues" --completion-promise "COMPLETE" --max-iterations 20
```

### Notes

- **Always set `--max-iterations`.** Without it the loop never ends and keeps
  spending tokens.
- The phrase is an **exact string match**. Use something that cannot appear by
  accident, such as `COMPLETE`, not `done`.
- **Do not put `$` or backticks in the task text**; the arguments go through
  bash.
- The state file is bound to the session that started the loop; other sessions
  in the same project are not affected.
- Best for tasks with **clear completion criteria that can be checked
  automatically** (tests, lint, build). Not for tasks that need human judgement
  or design decisions.
- Add `.claude/ralph-loop.local.md` to the project's `.gitignore`.

---

## 6. verify-gate: tests as the gate (written for this kit)

ralph-loop relies on Claude saying it is done. verify-gate decides from an
**objective check** instead. The two work well together.

### Enable it (per project)

Copy the template into **your project**:

```bash
cp /path/to/claude-self-review-kit/examples/verify.sh <your-project>/.claude/verify.sh
```

Then edit `.claude/verify.sh` and put in the real checks, for example
`make lint test`, `python -m pytest -q` or
`verilator --lint-only -Wall rtl/top.v`.

### Behaviour

| Situation | Result |
|---|---|
| The project has no `.claude/verify.sh` (and no `.chipagents/verify.sh`) | Nothing happens; other projects are unaffected |
| verify.sh exits 0 | Claude may stop |
| verify.sh exits non-zero | **Blocked**; the last 80 lines of output go back to Claude to fix |
| Blocked more than 10 times in a row | Claude may stop, so an unfixable failure cannot loop forever (set `VERIFY_GATE_MAX_BLOCKS` to change the limit) |

- verify.sh runs **every time** Claude tries to stop, so keep it fast,
  ideally under a minute; the hook's limit is 10 minutes.
- The block message explicitly forbids Claude from **editing or weakening
  verify.sh or the tests** to pass.
- Pause it by renaming `.claude/verify.sh`. Turn it off with
  `claude plugin disable verify-gate@self-review-kit`.
- Add `.claude/verify-gate.count` to `.gitignore`.

---

## 7. Self-review tools

### pr-review-toolkit (best for self-review)

Works on your **local `git diff`**; no GitHub needed.

```
/pr-review-toolkit:review-pr                # every aspect
/pr-review-toolkit:review-pr code errors    # general quality + error handling only
/pr-review-toolkit:review-pr all parallel   # all agents in parallel (faster, more tokens)
```

| Agent | Focus |
|---|---|
| `code-reviewer` | CLAUDE.md compliance, bugs, general code quality |
| `silent-failure-hunter` | Swallowed errors, empty catch blocks, bad fallbacks |
| `pr-test-analyzer` | Test coverage and test quality |
| `comment-analyzer` | Whether comments are accurate and up to date |
| `type-design-analyzer` | Type design, encapsulation, invariants |
| `code-simplifier` | Polishing after the review passes |

Findings are grouped as Critical, Important and Suggestions, with `file:line`.

### code-simplifier

An agent that makes recently changed code clearer without changing what it
does. Ask Claude to "use code-simplifier on the changes I just made".

### code-review (GitHub PRs only)

```
/code-review:code-review
```

- Reads a GitHub PR, runs 5 reviewers in parallel, then filters findings by a
  confidence score and keeps only those scoring 80 or more.
- **It finally posts the result as a comment on the PR with `gh`. That is
  public.**
- Needs GitHub, and you must run `gh auth login` yourself first.
- Claude Code also has a built-in `/code-review` (reviews the current diff;
  `--fix` applies fixes). To avoid confusion, call the plugin by its full name,
  `/code-review:code-review`.

### Built in, nothing to install

- `/code-review`: review the current diff; add `--fix` to apply fixes
- `/simplify`: code-quality cleanup only

---

## 8. Recommended setup

1. Put `.claude/verify.sh` in the project (verify-gate) → **no stopping while
   tests fail**.
2. Start the task with `/ralph-loop` and ask for a review every iteration (see
   the example in section 5) → **one iteration after another**.
3. Before finishing, run `/pr-review-toolkit:review-pr all` → **a final full
   check before a human looks at it**.

---

## 9. Changes from the official plugins

Compared with `diff -r` against the official copies Claude Code downloads;
**these are the only differences**:

1. **Fixed `pr-review-toolkit/agents/silent-failure-hunter.md`.**
   - The original `description:` is unquoted and contains `: `, so YAML parsing
     fails.
   - As a result the agent loads with an empty name and description, and
     `claude plugin validate` reports `✘ Validation failed`.
   - Fix: the description is wrapped in double quotes; the text is unchanged.
     It now validates.
2. All text files use **LF line endings**.
   - Git for Windows defaults to `core.autocrlf=true`, which turns `.sh` files
     into CRLF on a manual `git clone`, and bash then cannot run them.
   - A `.gitattributes` keeps `.sh` files LF.
3. Added the `verify-gate` plugin and `examples/verify.sh`.
4. Added files for ChipAgents, which Claude Code ignores (see section 13):
   - `ralph-loop` and `verify-gate` each gain `.chipagents-plugin/plugin.json`
     and `hooks/hooks.toml`
   - `ralph-loop/hooks/stop-hook-chipagents.sh`
   - `chipagents-test/`

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| ralph-loop does not start the next iteration | Usually jq is missing. Restart Claude Desktop so the new PATH applies, then check `jq --version` |
| `wsl: Unknown key ...` or `execvpe(/bin/bash) failed` | `bash` resolves to WSL's bash (in Windows PowerShell, `bash` often points to `WindowsApps\bash.exe`). In that plugin's `hooks/hooks.json`, replace `bash` with `"C:/Program Files/Git/bin/bash.exe"` |
| `$'\r': command not found` | The `.sh` file has CRLF line endings. Run `sed -i 's/\r$//' file.sh` |
| Plugin commands do not appear | Restart Claude Code after installing; check with `claude plugin list` |
| code-review fails | `gh auth login` has not been run, or the project is not on GitHub |

## 11. Uninstall

```bash
claude plugin uninstall ralph-loop@self-review-kit
```

```bash
claude plugin marketplace remove self-review-kit
```

## 12. License

- Official plugins: Apache License 2.0 (see the `LICENSE` in each plugin
  directory)
- verify-gate, chipagents-test and the rest of this kit: MIT (`LICENSE`)

---

## 13. Using it with ChipAgents

ChipAgents can install Claude Code marketplaces with `--type claude`, but it
**does not support Claude's `hooks/hooks.json`**; it uses its own
`hooks.toml`.

### Compatibility

| Plugin | In ChipAgents | Notes |
|---|---|---|
| `verify-gate` | ✅ Ported | Uses a `post_turn` hook with `blocking = true` and `enable_restarts = true`: when the check fails, ChipAgents reruns the agent with the error output |
| `ralph-loop` | ✅ Ported, used differently | Started from a terminal; completion is signalled with a file (see below) |
| `pr-review-toolkit` | ✅ Works | Agents and commands are supported. Claude-only fields such as `model`, `color` and `allowed-tools` may be ignored |
| `code-simplifier` | ⚠️ Loads | Its rules are written for JS/React, not RTL |
| `code-review` | ⚠️ Loads | GitHub PRs only; needs `gh` |

Claude Code's built-in `/code-review`, `/simplify` and `/loop` are not plugins,
so ChipAgents does not have them.

### Install (e.g. on CentOS)

```bash
chipagents plugin marketplace add githubhjs/claude-self-review-kit --type claude
chipagents plugin install verify-gate@self-review-kit
chipagents plugin install ralph-loop@self-review-kit
chipagents plugin install pr-review-toolkit@self-review-kit
```

If you install inside a running session, run `/reload` afterwards.

### verify-gate (ChipAgents)

- Put the check in `.chipagents/verify.sh`. `.claude/verify.sh` also works;
  when both exist `.claude/verify.sh` wins, so one script can serve both tools.
- It runs after every agent turn. On failure (non-zero exit) ChipAgents hands
  the last 80 lines of output to the agent and **reruns it to fix them**.
- The number of reruns is capped by `post_turn_restarts` (the plugin sets 10),
  plus the 10-blocks-in-a-row safety limit.
- One check may take up to 600 seconds.
- For RTL projects, verify.sh can run `slang`, `verilator --lint-only` or a
  small regression. ChipAgents also has a built-in `slang` hook type you can
  combine with it.

### ralph-loop (ChipAgents)

ChipAgents hooks only receive the previous turn's transcript text, which can
include your own prompt. If the prompt contains a `<promise>` tag, the loop
would think it is done, so **the ChipAgents version signals completion with a
file**.

1. Start the loop from a terminal in the project directory. **Do not use the
   `/ralph-loop` command**; that one is for Claude Code:

   ```bash
   bash /path/to/claude-self-review-kit/plugins/ralph-loop/scripts/setup-ralph-loop.sh "Make uart_tb pass" --completion-promise COMPLETE --max-iterations 10
   ```

2. Give ChipAgents the same task and add one line to the prompt: "When the task
   is completely done, run `echo COMPLETE > .claude/ralph-loop.promise`."
3. At the end of every turn the hook checks `.claude/ralph-loop.promise`:
   - Correct content, written during this iteration → the loop ends.
   - Missing, wrong content, or left over from an earlier loop → the same task
     goes back to the agent.
4. To cancel, delete the state file:

   ```bash
   rm .claude/ralph-loop.local.md
   ```

- `post_turn_restarts` must be **at least** `--max-iterations`. The plugin
  sets 20.
- This hook needs only bash, not jq.

### Notes

- **The first `post_turn_restarts` value found wins.** ChipAgents searches
  from the project directory upwards, then `~/.chipagents`. A value in the
  project's `.chipagents/hooks.toml` overrides the plugin's.
- **Preserved-thinking models** (the administrator set
  `thinkingRequiresIdenticalPrefix`): the ChipAgents docs warn that
  `post_turn` restarts can cause earlier thinking blocks to be dropped. Try it
  on a small scale first with such models.
- **Shell**: ChipAgents runs hooks with `$SHELL`. Under tcsh, common in EDA
  environments, the commands are just `bash "<path>"` and work fine.
- **E2E Mode is not an autonomous loop.** It is a test harness for the
  ChipAgents CLI, limited to 50 actions and 10 minutes per test. It is useful
  for checking that the setup above works.

### Checking verify-gate in ChipAgents (E2E test)

**The ChipAgents ports have only been tested with simulated input to the
scripts, not inside real ChipAgents.** Use this E2E test to check them:

```bash
mkdir /tmp/vg-test && cd /tmp/vg-test && git init -q && mkdir .chipagents
cp /path/to/claude-self-review-kit/chipagents-test/verify.sh .chipagents/verify.sh
chipagents validate ~/.chipagents          # or validate the plugin's hooks.toml
chipagents e2e-mode /path/to/claude-self-review-kit/chipagents-test/e2e-verify-gate.json
```

How the test works:
- It asks the agent to write `status: draft`, but verify.sh requires the file
  to say `status: ready`.
- **The test passes only if the hook really makes the agent rerun and fix
  it.**
- The report is written to `e2e-mode-run-*.log`.

To see what a hook actually receives, temporarily add this to the project's
`.chipagents/hooks.toml`, run one turn, and look at `/tmp/post-turn.json`:

```toml
[[post_turn]]
type = "bash"
command = "cat > /tmp/post-turn.json"
```

## Author

Chih-Hsueh "Josh" HUANG
