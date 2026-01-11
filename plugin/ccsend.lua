if vim.g.loaded_ccsend then return end
vim.g.loaded_ccsend = true

local ccsend = require("ccsend")

vim.api.nvim_create_user_command("CCSend", function(opts)
  ccsend.send(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Send prompt to Claude Code via ccsend",
})

vim.api.nvim_create_user_command("CCAdd", function(opts)
  ccsend.add(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Add prompt to **claude-code** buffer",
})

vim.api.nvim_create_user_command("CCSubmit", function()
  ccsend.submit()
end, {
  desc = "Submit **claude-code** buffer to Claude Code and delete it",
})
