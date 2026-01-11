local M = {}

local BUFFER_NAME = "**claude-code**"
local NS = vim.api.nvim_create_namespace("cctools-comment")

-- Track current comments: key = "filepath:line", value = {extmark_id, buf, comment}
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
  local comment_lines = {}

  for _, line in ipairs(lines) do
    -- Check for reference pattern: <file>:<start>-<end>:
    local filepath, start_line = line:match("^(.+):(%d+)-%d+:$")

    if filepath then
      local abs_path = vim.fn.fnamemodify(filepath, ":p")
      local line_num = tonumber(start_line)
      local key = abs_path .. ":" .. line_num
      local comment = vim.trim(table.concat(comment_lines, "\n"))

      refs[key] = {
        filepath = abs_path,
        line = line_num,
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

        local extmark_id = vim.api.nvim_buf_set_extmark(target_buf, NS, ref.line - 1, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })

        current_comments[key] = {
          extmark_id = extmark_id,
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

local function build_prompt(prompt, range)
  local full_prompt = prompt or ""

  if range and range > 0 then
    local selection, location = get_visual_selection()
    if selection and selection ~= "" then
      full_prompt = full_prompt .. "\n\n" .. location .. ":\n```\n" .. selection .. "\n```"
    end
  end

  return full_prompt
end

local function buffer_has_content()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  if buf == -1 then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  return vim.trim(text) ~= ""
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
  if text == "" then
    vim.notify("buffer is empty", vim.log.levels.WARN)
    return
  end

  send_to_claude(text, function()
    clear_all_comments()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end

return M
