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
- Comments appear as virtual lines above the referenced code in source files, cleared on submit
