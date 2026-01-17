# CLAUDE.md

Toolkit for integrating Claude Code with developer workflows via CLI utilities and a Neovim plugin.

## Project Structure

```
bin/
  cccode      # Bash wrapper: runs Claude Code with --permission-mode acceptEdits --model opus
  ccsend      # Bash script: sends prompts to Claude Code running in tmux pane
lua/cctools/
  init.lua    # Core Neovim plugin: buffer management, reference parsing, virtual comments, macro expansion
plugin/
  cctools.lua # Plugin entry: defines :CCSend, :CCAdd, :CC, :CCSubmit commands and key mappings
test/
  init.lua       # Isolated test environment configuration
  nvim-test      # Launch Neovim with plugin loaded from local directory
  run-tests      # Run all automated tests
  test_macros.lua # Automated tests for macro expansion
  manual_test.md  # Manual testing guide
.github/
  workflows/
    test.yml   # CI/CD: runs tests on PRs and main branch pushes
.editorconfig  # Editor configuration for consistent formatting
```

## Tech Stack

- **Bash** - CLI scripts (bin/), test runner (test/)
- **Lua** - Neovim plugin (lua/, plugin/), test scripts (test/)
- **tmux** - Process communication via `tmux send-keys`
- **pnpx** - Runs `@anthropic-ai/claude-code` package
- **Shellcheck** - Bash script linting and validation
- **GitHub Actions** - CI/CD for automated testing
- **EditorConfig** - Consistent formatting across editors

## Bash Conventions (bin/)

- Shebang: `#!/usr/bin/env bash`
- Always use `set -eu` (exit on error, undefined variables)
- Error messages to stderr: `echo "error: ..." >&2`
- Support both argument and stdin input patterns
- No external dependencies beyond standard Unix tools
- All scripts must pass shellcheck with no warnings

## Lua Conventions (lua/, plugin/)

- Module pattern: `local M = {} ... return M`
- Load guard: `if vim.g.loaded_<name> then return end`
- Use `vim.api.nvim_*` for Neovim API calls
- Use `vim.fn.*` for Vim functions
- Use `vim.bo[buf]` for buffer-local options
- Notifications via `vim.notify(msg, vim.log.levels.{INFO,WARN,ERROR})`
- Async operations via `vim.fn.jobstart()` with callbacks
- Virtual text via extmarks API (`nvim_buf_set_extmark`)

## Code Formatting

Project uses `.editorconfig` for consistent formatting across editors:
- **Indentation**: 2 spaces for all file types (Bash, Lua, YAML, Markdown)
- **Line endings**: LF (Unix-style)
- **Charset**: UTF-8
- **Trailing whitespace**: Trimmed (except in Markdown)
- **Final newline**: Always inserted

## Key Patterns

**Buffer naming**: Special buffers use `**name**` format (e.g., `**claude-code**`)

**Code references**: Format is `<file>:<start>-<end>:` - parsed by `parse_references()` in `lua/cctools/init.lua:18`

**Process tree walking**: `bin/ccsend` walks up the process tree from Claude PID to find the associated tmux pane

**Virtual line comments**: Extmarks with `virt_lines_above = true` display prompts above referenced code

**Macro expansion**: Prompts support `@file`, `@filename`, `@filepath` (git-relative or absolute path) and `@basename` (filename only). Macros expand via `expand_macros()` in `lua/cctools/init.lua:195` with word-boundary pattern matching. Uses `macro_map` table structure for easy extensibility.

**Key mappings**: Plugin defines `<leader>ac` (CCSend prompt), `<leader>aa` (CCAdd prompt), `<leader>as` (CCSubmit), and navigation keys `gC`, `]C`, `[C` for comment navigation. All defined in `plugin/cctools.lua`.

## Running/Testing

No build step. Install in Neovim via lazy.nvim:
```lua
{ dir = "~/path/to/cctools" }
```

**Production Usage:**
```bash
./bin/cccode                    # Launch Claude Code
./bin/ccsend "test prompt"      # Send to running instance
```

**Development Testing:**
```bash
./test/run-tests                # Run all automated tests (shellcheck + Lua tests)
./test/nvim-test [file...]      # Launch isolated test environment
```

Test suite includes:
- Shellcheck linting on all bash scripts (bin/*, test/*)
- Macro expansion tests (test/test_macros.lua)

**Neovim Commands (after loading):**
```vim
:CCSend test prompt             # Send prompt immediately
:CCAdd test                     # Add to staging buffer
:CC [prompt]                    # Add to staging buffer and switch to it
:CCSubmit                       # Submit staged buffer
```

**Neovim Key Mappings:**
```vim
<leader>ac                      # Prompt for CCSend input
<leader>aa                      # Prompt for CCAdd input
<leader>as                      # Execute CCSubmit
gC, ]C, [C                      # Navigate claude comments
```

**CI/CD:**
- Tests run automatically on PRs and pushes to `main`
- GitHub Actions workflow: `.github/workflows/test.yml`
- Installs Neovim (stable) and shellcheck
- Runs full test suite via `./test/run-tests`
