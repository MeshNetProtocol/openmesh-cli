# Claude Code Configuration

## File Operations Protocol (重要：文件操作规范)

所有 AI Agent 在此项目中执行文件读写时必须遵循以下规则，以防止 "Write failed" 错误：

1.  **始终使用相对路径**：禁止使用绝对路径（如 `/Users/wesley/...`）。所有路径必须相对于项目根目录（例如：`docs/phase1/task-cards/filename.md`）。
2.  **禁止预先使用 `touch`**：不要尝试通过 Bash 的 `touch` 命令创建空文件，然后执行写入。请直接调用 `write_to_file` 或 `FileWriteTool` 指定相对路径进行创建并写入内容。
    *   *原因*：预先 `touch` 会导致 AI 认为这是一个“已有文件”，如果没有先执行 `read` 操作就进行覆盖，会触发写保护而失败。
3.  **遵循 Read-Before-Write 流程**：
    *   如果目标文件已存在，必须先调用 `read_file` 确认内容。
    *   如果目标文件是新创建的，直接调用 `write` 工具。
4.  **自动创建目录**：在执行写入指令时，确保工具会自动创建不存在的父目录（`mkdir -p` 行为）。
5.  **编码要求**：所有文件名和内容必须使用 UTF-8 编码，特别是包含中文字符的路径。

## gstack

Use /browse from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.

Available skills: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /retro, /investigate, /document-release, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn, /pair-agent, /open-gstack-browser, /checkpoint, /health

## Project Context

This is the TweetPilot project - a Twitter/X automation and management tool.
*   **Tech Stack**: Vite, Electron, TS, Vitest.
*   **Architecture**: Slice-based vertical slices development.

