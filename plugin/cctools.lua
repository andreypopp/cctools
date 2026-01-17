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

vim.api.nvim_create_user_command("CC", function(opts)
  cctools.cc(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Add prompt to **claude-code** buffer and switch to it",
})

vim.api.nvim_create_user_command("CCSubmit", function()
  cctools.submit()
end, {
  desc = "Submit **claude-code** buffer to Claude Code and delete it",
})

-- Navigation keymaps
vim.keymap.set("n", "gC", cctools.goto_comment, { desc = "Go to claude comment for code under cursor" })
vim.keymap.set("n", "]C", cctools.next_comment, { desc = "Go to next claude comment" })
vim.keymap.set("n", "[C", cctools.prev_comment, { desc = "Go to previous claude comment" })

-- Command keymaps
vim.keymap.set("n", "<leader>ac", ":CCSend ", { desc = "CCSend: prompt for input" })
vim.keymap.set("v", "<leader>ac", ":CCSend ", { desc = "CCSend: prompt with selection" })
vim.keymap.set("n", "<leader>aa", ":CCAdd ", { desc = "CCAdd: prompt for input" })
vim.keymap.set("v", "<leader>aa", ":CCAdd ", { desc = "CCAdd: prompt with selection" })
vim.keymap.set("n", "<leader>as", "<cmd>CCSubmit<CR>", { desc = "CCSubmit: submit to Claude Code" })
