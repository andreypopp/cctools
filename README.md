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

Add to your config (e.g. lazy.nvim):
```lua
{ dir = "~/path/to/cctools" }
```

Commands:

- `:CCSend <prompt>` - Send prompt to Claude Code
- `:'<,'>CCSend <prompt>` - Send prompt with visual selection
- `:CCAdd <prompt>` - Add prompt to `**claude-code**` buffer
- `:'<,'>CCAdd <prompt>` - Add prompt with visual selection
- `:CCSubmit` - Send `**claude-code**` buffer contents and delete it

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
