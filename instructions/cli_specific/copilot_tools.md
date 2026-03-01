# GitHub Copilot CLI Tools

This section describes GitHub Copilot CLI-specific tools and features.

## Overview

GitHub Copilot CLI (`copilot`) is a standalone terminal-based AI coding agent. **NOT** the deprecated `gh copilot` extension (suggest/explain only). The standalone CLI uses the same agentic harness as GitHub's Copilot coding agent.

- **Launch**: `copilot` (interactive TUI)
- **Install**: `brew install copilot-cli` / `npm install -g @github/copilot` / `winget install GitHub.Copilot`
- **Auth**: GitHub account with active Copilot subscription. Env vars: `GH_TOKEN` or `GITHUB_TOKEN`
- **Default model**: Claude Sonnet 4.5

## Tool Usage

Copilot CLI provides tools requiring user approval before execution:

- **File operations**: touch, chmod, file read/write/edit
- **Execution tools**: node, sed, shell commands (via `!` prefix in TUI)
- **Network tools**: curl, wget, fetch
- **web_fetch**: Retrieves URL content as markdown (URL access controlled via `~/.copilot/config`)
- **MCP tools**: GitHub MCP server built-in (issues, PRs, Copilot Spaces), custom MCP servers via `/mcp add`

### Approval Model

- One-time permission or session-wide allowance per tool
- Bypass all: `--allow-all-paths`, `--allow-all-urls`, `--allow-all` / `--yolo`
- Tool filtering: `--available-tools` (allowlist), `--excluded-tools` (denylist)

## Interaction Model

Three interaction modes (cycle with **Shift+Tab**):

1. **Agent mode (Autopilot)**: Autonomous multi-step execution with tool calls
2. **Plan mode**: Collaborative planning before code generation
3. **Q&A mode**: Direct question-answer interaction

### Built-in Custom Agents

Invoke via `/agent` command, `--agent=<name>` flag, or reference in prompt:

| Agent | Purpose | Notes |
|-------|---------|-------|
| **Explore** | Fast codebase analysis | Runs in parallel, doesn't clutter main context |
| **Task** | Run commands (tests, builds) | Brief summary on success, full output on failure |
| **Plan** | Dependency analysis + planning | Analyzes structure before suggesting changes |
| **Code-review** | Review changes | High signal-to-noise ratio, genuine issues only |

Copilot automatically delegates to agents and runs multiple agents in parallel.

## Commands

| Command | Description |
|---------|-------------|
| `/model` | Switch model (Claude Sonnet 4.5, Claude Sonnet 4, GPT-5) |
| `/agent` | Select or invoke a built-in/custom agent |
| `/delegate` (or `&` prefix) | Push work to Copilot coding agent (remote) |
| `/resume` | Cycle through local/remote sessions (Tab to cycle) |
| `/compact` | Manual context compression |
| `/context` | Visualize token usage breakdown |
| `/review` | Code review |
| `/mcp add` | Add custom MCP server |
| `/add-dir` | Add directory to context |
| `/cwd` or `/cd` | Change working directory |
| `/login` | Authentication |
| `/lsp` | View LSP server status |
| `/feedback` | Submit feedback |
| `/clear`, `/new` | Clear conversation history (context reset) |
| `!<command>` | Execute shell command directly |
| `@path/to/file` | Include file as context (Tab to autocomplete) |

### Key Bindings

| Key | Action |
|-----|--------|
| **Esc** | Stop current operation / reject tool permission |
| **Shift+Tab** | Toggle plan mode |
| **Ctrl+T** | Toggle model reasoning visibility (persists across sessions) |
| **Tab** | Autocomplete file paths (`@` syntax), cycle `/resume` sessions |
| **Ctrl+S** | Save MCP server configuration |
| **?** | Display command reference |

## Custom Instructions

Copilot CLI reads instruction files automatically:

| File | Scope |
|------|-------|
| `.github/copilot-instructions.md` | Repository-wide instructions |
| `.github/instructions/**/*.instructions.md` | Path-specific (YAML frontmatter for glob patterns) |
| `AGENTS.md` | Repository root (shared with Codex CLI) |
| `CLAUDE.md` | Also read by Copilot coding agent |

Instructions **combine** (all matching files included in prompt). No priority-based fallback.

## MCP Configuration

- **Built-in**: GitHub MCP server (issues, PRs, Copilot Spaces) — pre-configured, enabled by default
- **Config file**: `~/.copilot/mcp-config.json` (JSON format)
- **Add server**: `/mcp add` in interactive mode, or `--additional-mcp-config <path>` per-session
- **URL control**: `allowed_urls` / `denied_urls` patterns in `~/.copilot/config`

## Context Management

- **Auto-compaction**: Triggered at 95% token limit
- **Manual compaction**: `/compact` command
- **Token visualization**: `/context` shows detailed breakdown
- **Session resume**: `--resume` (cycle sessions) or `--continue` (most recent local session)

## Model Switching

Available via `/model` command or `--model` flag. Models and Premium request costs (as of 2026-02-28):

| Model | Premium/req | Notes |
|-------|-------------|-------|
| **GPT-4.1** | **0** | Recommended for ashigaru (unlimited) |
| **GPT-5 mini** | **0** | Lightweight tasks (unlimited) |
| GPT-5.1-codex-mini | 0.33 | |
| Claude Haiku 4.5 | 0.33 | |
| Claude Sonnet 4/4.5/4.6 | 1 | Requires enablement on some plans |
| GPT-5.1/5.2/5.3-codex | 1 | |
| Gemini 3 Pro Preview | 1 | |
| Claude Opus 4.5/4.6 | 3 | High-cost |
| Claude Opus 4.6 fast | 30 | Preview, may require enablement |

For Ashigaru: Model set at startup via settings.yaml (`--model` flag). Runtime switching via `type: model_switch` available but rarely needed.

## tmux Interaction

**Verified on v0.0.420 (2026-02-28 tested).**

| Aspect | Status |
|--------|--------|
| TUI in tmux pane | ✅ Works |
| send-keys | ✅ Works — Enter sends prompt, text input received correctly |
| capture-pane | ✅ Works — response text readable, no alt-screen interference |
| Prompt detection | ✅ `❯` prompt visible in capture-pane output |
| Non-interactive pipe | ✅ `copilot -p "prompt" --model <model>` works |
| `/clear` via send-keys | ✅ Works — requires Enter×2 (1st=autocomplete select, 2nd=execute) |

### send-keys Notes
- Text input + Enter = prompt submission (single Enter suffices for normal messages)
- `/clear` + Enter×2 = context reset (autocomplete dropdown appears on first Enter)
- Ctrl+C = stop current operation (does NOT exit CLI)

## Limitations (vs Claude Code)

| Feature | Claude Code | Copilot CLI |
|---------|------------|-------------|
| tmux integration | ✅ Battle-tested | ✅ Verified (v0.0.420) |
| Non-interactive mode | ✅ `claude -p` | ✅ `copilot -p` |
| `/clear` context reset | ✅ Available | ✅ `/clear`, `/new` available |
| Memory MCP | ✅ Persistent knowledge graph | ❌ No equivalent |
| Cost model | Pro plan (rate-limited) | Subscription (premium req limits, GPT-4.1=0消費) |
| 8-agent parallel | ✅ Proven (but Pro rate-limited) | ✅ GPT-4.1 (0x) enables unlimited parallel |
| Dedicated file tools | ✅ Read/Write/Edit/Glob/Grep | General file tools with approval |
| Web search | ✅ WebSearch + WebFetch | web_fetch only |
| Task delegation | Task tool (local subagents) | /delegate (remote coding agent) |
| GitHub MCP | Via .mcp.json config | ✅ Built-in (issues, PRs, Copilot Spaces) |

## Compaction & Recovery

Copilot CLI uses auto-compaction at 95% token limit. `/clear` and `/new` are also available for full context reset.

For the 将軍 system:
1. Auto-compaction handles most cases automatically
2. `/clear` via send-keys works (Enter×2 required for autocomplete)
3. `/compact` for manual context reduction without full reset
4. On `/clear`, agent recovers via `.github/copilot-instructions.md` (auto-loaded) → Session Start procedure

## Configuration Files Summary

| File | Location | Purpose |
|------|----------|---------|
| `config` / `config.json` | `~/.copilot/` | Main configuration |
| `mcp-config.json` | `~/.copilot/` | MCP server definitions |
| `lsp-config.json` | `~/.copilot/` | LSP server configuration |
| `.github/lsp.json` | Repo root | Repository-level LSP config |

Location customizable via `XDG_CONFIG_HOME` environment variable.

---

*Sources: [GitHub Copilot CLI Docs](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli), [Copilot CLI Repository](https://github.com/github/copilot-cli), [Enhanced Agents Changelog (2026-01-14)](https://github.blog/changelog/2026-01-14-github-copilot-cli-enhanced-agents-context-management-and-new-ways-to-install/), [Plan Mode Changelog (2026-01-21)](https://github.blog/changelog/2026-01-21-github-copilot-cli-plan-before-you-build-steer-as-you-go/), [PR #10 (yuto-ts) Copilot対応](https://github.com/yohey-w/multi-agent-shogun/pull/10)*
