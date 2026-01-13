if vim.g.loaded_cctools then return end
vim.g.loaded_cctools = true

local cctools = require("cctools")

vim.api.nvim_create_user_command("CCSend", function(opts)
  cctools.send(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Send prompt to Claude Code",
})

vim.api.nvim_create_user_command("CCAdd", function(opts)
  cctools.add(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Add prompt to **claude-code** buffer",
})

vim.api.nvim_create_user_command("CCSubmit", function()
  cctools.submit()
end, {
  desc = "Submit **claude-code** buffer to Claude Code and delete it",
})

vim.keymap.set("n", "gC", cctools.goto_comment, { desc = "Go to claude comment for code under cursor" })
vim.keymap.set("n", "]C", cctools.next_comment, { desc = "Go to next claude comment" })
vim.keymap.set("n", "[C", cctools.prev_comment, { desc = "Go to previous claude comment" })
