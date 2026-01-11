# CLAUDE.md

Toolkit for integrating Claude Code with developer workflows via CLI utilities and a Neovim plugin.

## Project Structure

```
bin/
  cccode     # Bash wrapper: runs Claude Code with --permission-mode acceptEdits --model opus
  ccsend     # Bash script: sends prompts to Claude Code running in tmux pane
lua/ccsend/
  init.lua   # Core Neovim plugin: buffer management, reference parsing, virtual comments
plugin/
  ccsend.lua # Plugin entry: defines :CCSend, :CCAdd, :CCSubmit commands
```

## Tech Stack

- **Bash** - CLI scripts (bin/)
- **Lua** - Neovim plugin (lua/, plugin/)
- **tmux** - Process communication via `tmux send-keys`
- **pnpx** - Runs `@anthropic-ai/claude-code` package

## Bash Conventions (bin/)

- Shebang: `#!/usr/bin/env bash`
- Always use `set -eu` (exit on error, undefined variables)
- Error messages to stderr: `echo "error: ..." >&2`
- Support both argument and stdin input patterns
- No external dependencies beyond standard Unix tools

## Lua Conventions (lua/, plugin/)

- Module pattern: `local M = {} ... return M`
- Load guard: `if vim.g.loaded_<name> then return end`
- Use `vim.api.nvim_*` for Neovim API calls
- Use `vim.fn.*` for Vim functions
- Use `vim.bo[buf]` for buffer-local options
- Notifications via `vim.notify(msg, vim.log.levels.{INFO,WARN,ERROR})`
- Async operations via `vim.fn.jobstart()` with callbacks
- Virtual text via extmarks API (`nvim_buf_set_extmark`)

## Key Patterns

**Buffer naming**: Special buffers use `**name**` format (e.g., `**claude-code**`)

**Code references**: Format is `<file>:<start>-<end>:` - parsed by `parse_references()` in `lua/ccsend/init.lua:18`

**Process tree walking**: `bin/ccsend` walks up the process tree from Claude PID to find the associated tmux pane

**Virtual line comments**: Extmarks with `virt_lines_above = true` display prompts above referenced code

## Running/Testing

No build step. Install in Neovim via lazy.nvim:
```lua
{ dir = "~/path/to/cctools" }
```

Test CLI scripts directly:
```bash
./bin/cccode                    # Launch Claude Code
./bin/ccsend "test prompt"      # Send to running instance
```

Test Neovim commands after loading the plugin:
```vim
:CCSend test prompt
:CCAdd test
:CCSubmit
```
