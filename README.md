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

The `**claude-code**` buffer has `<leader><CR>` mapped to `:CCSubmit`.
