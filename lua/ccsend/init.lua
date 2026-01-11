local M = {}

local BUFFER_NAME = "**claude-code**"

local function get_or_create_buffer()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, BUFFER_NAME)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "<leader><CR>", "<cmd>CCSubmit<CR>", { buffer = buf, desc = "Submit to Claude Code" })
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

local function send_to_claude(text)
  local ccsend_path = get_ccsend_path()

  if vim.fn.filereadable(ccsend_path) == 0 then
    vim.notify("ccsend not found at: " .. ccsend_path, vim.log.levels.ERROR)
    return false
  end

  local job = vim.fn.jobstart({ ccsend_path }, {
    stdin = "pipe",
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("Sent to Claude Code", vim.log.levels.INFO)
      else
        vim.notify("Failed to send (exit: " .. code .. ")", vim.log.levels.ERROR)
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
    vim.list_extend(lines, new_lines)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  vim.notify("Added to " .. BUFFER_NAME, vim.log.levels.INFO)
end

function M.submit()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  if buf == -1 then
    vim.notify("No " .. BUFFER_NAME .. " buffer found", vim.log.levels.WARN)
    return
  end

  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if text == "" then
    vim.notify("Buffer is empty", vim.log.levels.WARN)
    return
  end

  if send_to_claude(text) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

return M
