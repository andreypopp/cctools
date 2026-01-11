if vim.g.loaded_ghreview then return end
vim.g.loaded_ghreview = true

local ghreview = require("ghreview")

vim.api.nvim_create_user_command("GHComment", function(opts)
  ghreview.add(opts.args, { range = opts.range })
end, {
  nargs = "*",
  range = true,
  desc = "Add comment to **github-review** buffer",
})

vim.api.nvim_create_user_command("GHSubmit", function()
  ghreview.submit()
end, {
  desc = "Submit all comments to GitHub PR",
})

vim.api.nvim_create_user_command("GHReview", function()
  ghreview.open()
end, {
  desc = "Open **github-review** buffer",
})

vim.keymap.set("n", "gR", ghreview.goto_comment, { desc = "Go to GitHub review comment for code under cursor" })
