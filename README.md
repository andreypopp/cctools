# cctools

Tools for working with Claude Code.

## Command Line

**bin/cccode** - Run Claude Code with defaults (accepts edits, opus model):
```
cccode
```

**bin/ccsend** - Send text to Claude Code running in a tmux pane:
```
ccsend "your prompt here"
echo "your prompt" | ccsend
```

## Neovim Plugin

Using [Lazy](https://github.com/folke/lazy.nvim):

```lua
return {
  "andreypopp/cctools"
}
```
Commands:

- `:CCSend <prompt>` - Send prompt to Claude Code
- `:'<,'>CCSend <prompt>` - Send prompt with visual selection
- `:CCAdd <prompt>` - Add prompt to `**claude-code**` buffer
- `:'<,'>CCAdd <prompt>` - Add prompt with visual selection
- `:CCSubmit` - Send `**claude-code**` buffer contents and delete it

Key Mappings:

- `<leader>ac` - Prompt for `:CCSend` input (normal/visual mode)
- `<leader>aa` - Prompt for `:CCAdd` input (normal/visual mode)
- `<leader>as` - Execute `:CCSubmit` immediately
- `gC` - Jump to claude comment for code under cursor
- `]C` / `[C` - Navigate to next/previous claude comment

### The `**claude-code**` Buffer

The `**claude-code**` buffer lets you compose multi-part prompts before sending. Use `:CCAdd` to accumulate code snippets with comments, then `:CCSubmit` to send everything at once.

Example workflow:
```
:'<,'>CCAdd refactor this function      " Select code, add with comment
:'<,'>CCAdd also update these tests     " Add more code
:CCSubmit                               " Send entire buffer
```

Features:
- `<leader><CR>` is mapped to `:CCSubmit` in the buffer
- Code references use the format `<file>:<start>-<end>:` - use `gF` to jump to the referenced location
- In source files, use `gC` to jump to the claude comment for the code under cursor
- Comments appear as virtual lines above the referenced code in source files, cleared on submit

### Highlight Groups

The plugin defines two highlight groups for customization:

- **`CCToolsComment`** - Used for virtual comment lines above referenced code. Linked to `Comment` by default.
- **`CCToolsCode`** - Used to highlight the referenced code lines. Linked to `DiffText` by default.

To customize, define these in your colorscheme or config:
```lua
vim.api.nvim_set_hl(0, "CCToolsComment", { fg = "#888888", italic = true })
vim.api.nvim_set_hl(0, "CCToolsCode", { bg = "#2d3f4f" })
```

### Macros

Prompts support macro expansion that happens automatically before sending to Claude:

**`@file`** (aliases: `@filename`, `@filepath`) - Expands to the current buffer's file path:
- If in a git repository: path relative to git root (e.g., `src/main.lua`)
- If not in a git repo: absolute path (e.g., `/home/user/project/main.lua`)
- If buffer has no file: macro is preserved unchanged

**`@basename`** - Expands to just the filename (no directory path):
- Example: `main.lua` (regardless of git context)

Examples:
```vim
:CCSend review @file for bugs
" Sends: "review src/main.lua for bugs"

:CCAdd refactor @file to use async patterns
" Adds to buffer: "refactor src/main.lua to use async patterns"

:CCSend rename @basename to something more descriptive
" Sends: "rename main.lua to something more descriptive"

:CCAdd compare @basename with @file
" Shows both filename only and full path in one prompt
```

Macros respect word boundaries, so `email@file.com` won't expand.

## Development

### Running Tests

Run all automated tests:
```bash
./test/run-tests
```

This runs:
- **Shellcheck** - Lints all bash scripts in `bin/` and `test/`
- **Macro expansion tests** - Validates `@file`, `@basename` macros

Shellcheck is optional - tests will skip it with a warning if not installed.

### Test Environment

Launch Neovim with the plugin loaded from local directory:
```bash
./test/nvim-test [file...]
```

This creates an isolated test environment with:
- Plugin loaded from current directory (not installed version)
- Test data stored in `.test-data/` (gitignored)
- Minimal sensible defaults

### CI/CD

Tests automatically run on:
- Pull requests to `main`
- Pushes to `main` branch

CI environment includes:
- Latest stable Neovim
- Shellcheck for bash script linting
- All test suites (shellcheck + macro tests)

See `.github/workflows/test.yml` for configuration.
