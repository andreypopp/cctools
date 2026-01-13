-- Minimal test environment for cctools plugin development
-- Usage: nvim -u test/init.lua

-- Set up isolated data directory
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
local data_dir = root .. ".test-data"
vim.fn.mkdir(data_dir, "p")

-- Set paths for isolated environment
vim.opt.runtimepath:prepend(data_dir .. "/lazy/lazy.nvim")
vim.opt.runtimepath:prepend(root)

-- Bootstrap lazy.nvim
local lazypath = data_dir .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

-- Basic sensible defaults
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.termguicolors = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.syntax = "on"

-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Setup lazy.nvim and load cctools from current directory
require("lazy").setup({
  {
    name = "cctools",
    dir = root,
    config = function()
      -- Plugin auto-loads via plugin/cctools.lua
    end,
  },
}, {
  root = data_dir .. "/lazy",
  lockfile = data_dir .. "/lazy-lock.json",
})

-- Status message
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.notify("cctools test environment loaded from: " .. root, vim.log.levels.INFO)
    vim.notify("Commands: :CCSend, :CCAdd, :CCSubmit", vim.log.levels.INFO)
    vim.notify("Keymaps: gC, ]C, [C", vim.log.levels.INFO)
  end,
})
