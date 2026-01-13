-- Test script for key mappings
-- Run with: nvim -u test/init.lua -l test/test_keymaps.lua

print("\n=== Key Mapping Tests ===\n")

-- Wait for plugin to load
vim.cmd("sleep 100m")

local passed = 0
local failed = 0

-- Helper to check if a keymap exists
local function check_keymap(mode, lhs, expected_desc)
  local maps = vim.api.nvim_get_keymap(mode)
  for _, map in ipairs(maps) do
    if map.lhs == lhs then
      local status = "✓ PASS"
      passed = passed + 1
      print(string.format("%s [%s] %s exists", status, mode, lhs))
      if expected_desc and map.desc then
        print(string.format("  Description: %s", map.desc))
      end
      return true
    end
  end

  local status = "✗ FAIL"
  failed = failed + 1
  print(string.format("%s [%s] %s not found", status, mode, lhs))
  return false
end

-- Test leader-based command mappings
-- Leader is set to space in test environment
local leader = vim.g.mapleader or " "
check_keymap("n", leader .. "ac", "CCSend: prompt for input")
check_keymap("v", leader .. "ac", "CCSend: prompt with selection")
check_keymap("n", leader .. "aa", "CCAdd: prompt for input")
check_keymap("v", leader .. "aa", "CCAdd: prompt with selection")
check_keymap("n", leader .. "as", "CCSubmit: submit to Claude Code")

-- Test navigation mappings
check_keymap("n", "gC", "Go to claude comment")
check_keymap("n", "]C", "Go to next claude comment")
check_keymap("n", "[C", "Go to previous claude comment")

print(string.format("\nResults: %d passed, %d failed", passed, failed))

-- Exit with appropriate code
if failed > 0 then
  vim.cmd("cquit")
else
  vim.cmd("quit")
end
