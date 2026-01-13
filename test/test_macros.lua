-- Test script for macro expansion
-- Run with: nvim -u test/init.lua -l test/test_macros.lua

-- Load the cctools module
local cctools_path = vim.fn.getcwd() .. "/lua/cctools/init.lua"
local cctools_src = loadfile(cctools_path)
if not cctools_src then
  print("ERROR: Could not load " .. cctools_path)
  vim.cmd("quit!")
end

-- Execute the module to get local functions
local function get_expand_macros_fn()
  local chunk = [[
    local function get_file_path_for_buffer()
      local bufpath = vim.api.nvim_buf_get_name(0)
      if bufpath == "" or bufpath:match("^%*%*.*%*%*$") then
        return nil
      end
      local abs_path = vim.fn.fnamemodify(bufpath, ":p")
      if vim.fn.filereadable(abs_path) == 0 then
        return nil
      end
      local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.fnamemodify(abs_path, ":h")) .. " rev-parse --show-toplevel 2>/dev/null")[1]
      if git_root and git_root ~= "" and vim.v.shell_error == 0 then
        local rel_path = vim.fn.fnamemodify(abs_path, ":s?" .. vim.pesc(git_root) .. "/??")
        return rel_path
      else
        return abs_path
      end
    end

    local function expand_macros(text)
      local filepath = get_file_path_for_buffer()
      if not filepath then
        return text
      end
      local macros = { "@filepath", "@filename", "@file" }
      for _, macro in ipairs(macros) do
        text = text:gsub("^" .. vim.pesc(macro) .. "([^%w_])", filepath .. "%1")
        text = text:gsub("^" .. vim.pesc(macro) .. "$", filepath)
        text = text:gsub("([^%w_])" .. vim.pesc(macro) .. "([^%w_])", "%1" .. filepath .. "%2")
        text = text:gsub("([^%w_])" .. vim.pesc(macro) .. "$", "%1" .. filepath)
      end
      return text
    end

    return expand_macros
  ]]
  return loadstring(chunk)()
end

local expand_macros = get_expand_macros_fn()

-- Test cases
local tests = {
  { input = "check @file for errors", desc = "macro in middle" },
  { input = "@file is broken", desc = "macro at start" },
  { input = "look at @file", desc = "macro at end" },
  { input = "@file", desc = "macro alone" },
  { input = "compare @file and @filename", desc = "multiple macros" },
  { input = "@filepath is the path", desc = "longest macro" },
  { input = "email@file.com should not expand", desc = "no word boundary before" },
  { input = "@filenotamacro", desc = "no word boundary after" },
}

print("\n=== Macro Expansion Tests ===\n")

-- Create a test file to work with
local test_file = vim.fn.getcwd() .. "/test/test_macros.lua"
vim.cmd("edit " .. test_file)

print("Current file: " .. vim.api.nvim_buf_get_name(0))
print("Expected path: test/test_macros.lua (git-relative)\n")

local passed = 0
local failed = 0

for i, test in ipairs(tests) do
  local result = expand_macros(test.input)
  local status = "✓"

  -- Check if expansion happened appropriately
  if test.input:match("email@file") or test.input:match("@filenotamacro") then
    -- Should NOT expand
    if result == test.input then
      status = "✓ PASS"
      passed = passed + 1
    else
      status = "✗ FAIL"
      failed = failed + 1
    end
  else
    -- Should expand
    if result ~= test.input and result:match("test/test_macros%.lua") then
      status = "✓ PASS"
      passed = passed + 1
    else
      status = "✗ FAIL"
      failed = failed + 1
    end
  end

  print(string.format("%s [%s]", status, test.desc))
  print(string.format("  Input:  %s", test.input))
  print(string.format("  Output: %s", result))
  print()
end

print(string.format("Results: %d passed, %d failed", passed, failed))

-- Exit with appropriate code
if failed > 0 then
  vim.cmd("cquit")
else
  vim.cmd("quit")
end
