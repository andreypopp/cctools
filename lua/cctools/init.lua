local M = {}

local BUFFER_NAME = "**claude-code**"
local NS = vim.api.nvim_create_namespace("cctools-comment")

---@type table<string, {extmark_id: integer, hl_extmark_id: integer, buf: integer, comment: string}>
local current_comments = {}

local function clear_all_comments()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    end
  end
  current_comments = {}
end

local function parse_references(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local refs = {}
  local comment_lines = {} -- Accumulates lines until we hit a reference

  for _, line in ipairs(lines) do
    -- Check for reference pattern: <file>:<start>-<end>:
    local filepath, start_line, end_line = line:match("^(.+):(%d+)-(%d+):$")

    if filepath then
      local abs_path = vim.fn.fnamemodify(filepath, ":p")
      local start_num = tonumber(start_line)
      local end_num = tonumber(end_line)
      local key = abs_path .. ":" .. start_num
      -- Trim empty lines from end
      while #comment_lines > 0 and vim.trim(comment_lines[#comment_lines]) == "" do
        table.remove(comment_lines)
      end
      -- Trim empty lines from start
      while #comment_lines > 0 and vim.trim(comment_lines[1]) == "" do
        table.remove(comment_lines, 1)
      end
      -- Prefix each line with gutter marker
      for i, l in ipairs(comment_lines) do
        comment_lines[i] = "claude: " .. l
      end
      local comment = table.concat(comment_lines, "\n")

      refs[key] = {
        filepath = abs_path,
        start_line = start_num,
        end_line = end_num,
        comment = comment,
      }
      comment_lines = {}
    elseif line == "---" then
      comment_lines = {}
    else
      table.insert(comment_lines, line)
    end
  end

  return refs
end

local function reconcile_comments(new_refs)
  -- Remove comments that no longer exist or changed
  for key, data in pairs(current_comments) do
    local new_ref = new_refs[key]
    if not new_ref or new_ref.comment ~= data.comment then
      if vim.api.nvim_buf_is_valid(data.buf) then
        vim.api.nvim_buf_del_extmark(data.buf, NS, data.extmark_id)
        vim.api.nvim_buf_del_extmark(data.buf, NS, data.hl_extmark_id)
      end
      current_comments[key] = nil
    end
  end

  -- Add new or updated comments
  for key, ref in pairs(new_refs) do
    if not current_comments[key] and ref.comment ~= "" then
      -- Find or load the buffer for this file
      local target_buf = vim.fn.bufnr(ref.filepath)
      if target_buf ~= -1 and vim.api.nvim_buf_is_valid(target_buf) then
        local virt_lines = {}
        for _, l in ipairs(vim.split(ref.comment, "\n")) do
          table.insert(virt_lines, { { l, "Comment" } })
        end

        local extmark_id = vim.api.nvim_buf_set_extmark(target_buf, NS, ref.start_line - 1, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })

        -- Highlight the referenced lines
        local hl_extmark_id = vim.api.nvim_buf_set_extmark(target_buf, NS, ref.start_line - 1, 0, {
          end_row = ref.end_line,
          hl_group = "DiffText",
          hl_eol = true,
        })

        current_comments[key] = {
          extmark_id = extmark_id,
          hl_extmark_id = hl_extmark_id,
          buf = target_buf,
          comment = ref.comment,
        }
      end
    end
  end
end

local function on_claude_buffer_change(buf)
  local refs = parse_references(buf)
  reconcile_comments(refs)
end

local function get_or_create_buffer()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, BUFFER_NAME)
    vim.bo[buf].buftype = "acwrite"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "<leader><CR>", "<cmd>CCSubmit<CR>", { buffer = buf, desc = "Submit to Claude Code" })

    -- Attach to buffer for change tracking
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            on_claude_buffer_change(buf)
          end
        end)
      end,
      on_detach = function()
        clear_all_comments()
      end,
    })
  end
  return buf
end

local function get_ccsend_path()
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h")
  return plugin_dir .. "/bin/ccsend"
end

local function get_visual_selection()
  local _, start_line, start_col = unpack(vim.fn.getpos("'<"))
  local _, end_line, end_col = unpack(vim.fn.getpos("'>"))

  local lines = vim.fn.getline(start_line, end_line)
  if #lines == 0 then return nil end

  if #lines == 1 then
    lines[1] = lines[1]:sub(start_col, end_col)
  else
    lines[1] = lines[1]:sub(start_col)
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end

  local location = vim.fn.expand("%:.") .. ":" .. start_line .. "-" .. end_line
  return table.concat(lines, "\n"), location
end

local function get_file_path_for_buffer()
  local bufpath = vim.api.nvim_buf_get_name(0)

  -- Check if buffer has a file path and it's not a special buffer
  if bufpath == "" or bufpath:match("^%*%*.*%*%*$") then
    return nil
  end

  -- Get absolute path
  local abs_path = vim.fn.fnamemodify(bufpath, ":p")

  -- Check if file exists
  if vim.fn.filereadable(abs_path) == 0 then
    return nil
  end

  -- Try to find git root
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.fnamemodify(abs_path, ":h")) .. " rev-parse --show-toplevel 2>/dev/null")[1]

  if git_root and git_root ~= "" and vim.v.shell_error == 0 then
    -- File is in a git repo, return relative path
    local rel_path = vim.fn.fnamemodify(abs_path, ":s?" .. vim.pesc(git_root) .. "/??")
    return rel_path
  else
    -- Not in a git repo, return absolute path
    return abs_path
  end
end

local function expand_macros(text)
  local filepath = get_file_path_for_buffer()

  -- If we can't get a file path, return text unchanged
  if not filepath then
    return text
  end

  -- Replace macros with word boundaries
  -- Order matters: longest patterns first to avoid partial matches
  local macros = { "@filepath", "@filename", "@file" }

  for _, macro in ipairs(macros) do
    -- Match at start of string
    text = text:gsub("^" .. vim.pesc(macro) .. "([^%w_])", filepath .. "%1")
    text = text:gsub("^" .. vim.pesc(macro) .. "$", filepath)
    -- Match in middle or end with word boundary
    text = text:gsub("([^%w_])" .. vim.pesc(macro) .. "([^%w_])", "%1" .. filepath .. "%2")
    text = text:gsub("([^%w_])" .. vim.pesc(macro) .. "$", "%1" .. filepath)
  end

  return text
end

local function build_prompt(prompt, range)
  local full_prompt = prompt or ""

  if range and range > 0 then
    local selection, location = get_visual_selection()
    if selection and selection ~= "" then
      full_prompt = full_prompt .. "\n\n" .. location .. ":\n```\n" .. selection .. "\n```"
    end
  end

  -- Expand macros in the prompt
  full_prompt = expand_macros(full_prompt)

  return full_prompt
end

local function send_to_claude(text, on_success)
  local ccsend_path = get_ccsend_path()

  if vim.fn.filereadable(ccsend_path) == 0 then
    vim.notify("ccsend not found at: " .. ccsend_path, vim.log.levels.ERROR)
    return false
  end

  local job = vim.fn.jobstart({ ccsend_path }, {
    stdin = "pipe",
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("sent to Claude Code", vim.log.levels.INFO)
        if on_success then on_success() end
      else
        vim.notify("failed to send (exit: " .. code .. ")", vim.log.levels.ERROR)
      end
    end,
    on_stderr = function(_, data)
      local msg = table.concat(data, "\n")
      if msg ~= "" then vim.notify(msg, vim.log.levels.ERROR) end
    end,
  })

  if job <= 0 then
    vim.notify("Failed to start ccsend", vim.log.levels.ERROR)
    return false
  end

  vim.fn.chansend(job, text)
  vim.fn.chanclose(job, "stdin")
  return true
end

function M.send(prompt, opts)
  local text = build_prompt(prompt, opts and opts.range)
  if text == "" then
    vim.notify("No prompt provided", vim.log.levels.WARN)
    return
  end
  send_to_claude(text)
end

function M.add(prompt, opts)
  local text = build_prompt(prompt, opts and opts.range)
  if text == "" then
    vim.notify("Nothing to add", vim.log.levels.WARN)
    return
  end

  local buf = get_or_create_buffer()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local new_lines = vim.split(text, "\n")

  if #lines == 1 and lines[1] == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  else
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
    vim.list_extend(lines, new_lines)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  vim.bo[buf].modified = true
  vim.notify("added to " .. BUFFER_NAME, vim.log.levels.INFO)
end

function M.submit()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  if buf == -1 then
    vim.notify("no " .. BUFFER_NAME .. " buffer found", vim.log.levels.WARN)
    return
  end

  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if vim.trim(text) == "" then
    vim.notify("buffer is empty", vim.log.levels.WARN)
    return
  end

  send_to_claude(text, function()
    clear_all_comments()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end

local function get_comment_lines_in_buffer(buf)
  local lines = {}
  for _, data in pairs(current_comments) do
    if data.buf == buf then
      local extmark = vim.api.nvim_buf_get_extmark_by_id(buf, NS, data.extmark_id, {})
      if extmark and #extmark > 0 then
        table.insert(lines, extmark[1] + 1) -- Convert to 1-indexed
      end
    end
  end
  table.sort(lines)
  return lines
end

function M.next_comment()
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.fn.line(".")
  local lines = get_comment_lines_in_buffer(buf)

  for _, line in ipairs(lines) do
    if line > cursor_line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      return
    end
  end

  if #lines > 0 then
    vim.api.nvim_win_set_cursor(0, { lines[1], 0 })
  else
    vim.notify("no comments in buffer", vim.log.levels.WARN)
  end
end

function M.prev_comment()
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.fn.line(".")
  local lines = get_comment_lines_in_buffer(buf)

  for i = #lines, 1, -1 do
    if lines[i] < cursor_line then
      vim.api.nvim_win_set_cursor(0, { lines[i], 0 })
      return
    end
  end

  if #lines > 0 then
    vim.api.nvim_win_set_cursor(0, { lines[#lines], 0 })
  else
    vim.notify("no comments in buffer", vim.log.levels.WARN)
  end
end

function M.goto_comment()
  local claude_buf = vim.fn.bufnr(BUFFER_NAME)
  if claude_buf == -1 then
    vim.notify("no " .. BUFFER_NAME .. " buffer", vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  local current_line = vim.fn.line(".")

  local lines = vim.api.nvim_buf_get_lines(claude_buf, 0, -1, false)
  local target_line_nr = nil

  for i, line in ipairs(lines) do
    local filepath, start_line, end_line = line:match("^(.+):(%d+)-(%d+):$")
    if filepath then
      local abs_path = vim.fn.fnamemodify(filepath, ":p")
      local start_num = tonumber(start_line)
      local end_num = tonumber(end_line)
      if abs_path == current_file and current_line >= start_num and current_line <= end_num then
        target_line_nr = i
        break
      end
    end
  end

  if not target_line_nr then
    vim.notify("no comment for this location", vim.log.levels.WARN)
    return
  end

  -- Find window with claude buffer or open in current window
  local claude_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == claude_buf then
      claude_win = win
      break
    end
  end

  if claude_win then
    vim.api.nvim_set_current_win(claude_win)
  else
    vim.cmd("buffer " .. claude_buf)
  end

  vim.api.nvim_win_set_cursor(0, { target_line_nr, 0 })
end

return M
