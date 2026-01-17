# cctools

Neovim plugin and CLI tools for Claude Code. The tools and the plugin assume
that there's a **single Claude Code instance running within the tmux session**.

## CLI

```bash
cccode                      # Run Claude Code (--permission-mode acceptEdits --model opus)
ccsend "prompt"             # Send to Claude Code in tmux pane
echo "prompt" | ccsend      # Send via stdin
```

## Neovim Plugin

```lua
{ "andreypopp/cctools" }    -- lazy.nvim
```

### Commands

- `:CCSend <prompt>` — send prompt to Claude Code
- `:CCAdd <prompt>` — add prompt to `**claude-code**` staging buffer
- `:CC <prompt>` — add prompt to `**claude-code**` staging buffer and switch to it
- `:CCSubmit` — send `**claude-code**` buffer to Claude Code

All commands accept visual selection (`:'<,'>CCSend ...`). In this case
comments will appear above the selected code as virtual lines.

### Key Mappings

- `<leader>ac` — prompt for CCSend
- `<leader>aa` — prompt for CCAdd
- `<leader>as` — submit staging buffer
- `gC` — jump to comment for code under cursor
- `]C` / `[C` — next/prev comment

### Staging Buffer (`**claude-code**`)

Compose multi-part prompts before sending:

```vim
:'<,'>CCAdd refactor this
:'<,'>CCAdd update tests
:CCSubmit
```

- `<leader><CR>` submits from within buffer
- References (`file:start-end:`) navigable with `gF`

### Macros

Expanded automatically in prompts:

- `@file` (`@filename`, `@filepath`) — git-relative or absolute path
- `@basename` — filename only

```vim
:CCSend review @file    " → "review src/main.lua"
```

### Highlight Groups

- `CCToolsComment` (default: `Comment`) — virtual comment lines
- `CCToolsCode` (default: `DiffText`) — referenced code highlight
