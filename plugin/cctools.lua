if vim.g.loaded_cctools then return end
vim.g.loaded_cctools = true

local cctools = require("cctools")

local function get_range(range)
  if range == 0 then return nil end
  local _, start_line, start_col = unpack(vim.fn.getpos("'<"))
  local _, end_line, end_col = unpack(vim.fn.getpos("'>"))
  return {
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

vim.api.nvim_create_user_command("CCSend", function(opts)
  local range = get_range(opts.range)
  if opts.args == "" then
    vim.ui.input({ prompt = "CCSend: " }, function(input)
      if input and input ~= "" then
        cctools.send(input, {range=range})
      end
    end)
  else
    cctools.send(opts.args, {range=range})
  end
end, {
  nargs = "*",
  range = true,
  desc = "Send prompt to Claude Code",
})

vim.api.nvim_create_user_command("CCAdd", function(opts)
  local range = get_range(opts.range)
  if opts.args == "" then
    vim.ui.input({ prompt = "CCAdd: " }, function(input)
      if input and input ~= "" then
        cctools.add(input, {range=range})
      end
    end)
  else
    cctools.add(opts.args, {range=range})
  end
end, {
  nargs = "*",
  range = true,
  desc = "Add prompt to **claude-code** buffer",
})

vim.api.nvim_create_user_command("CC", function(opts)
  local range = get_range(opts.range)
  cctools.cc(opts.args, {range=range})
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
