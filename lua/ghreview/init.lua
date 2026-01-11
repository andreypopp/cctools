local M = {}

local BUFFER_NAME = "**github-review**"
local NS = vim.api.nvim_create_namespace("ghreview-comment")

---@type table<string, {extmark_id: integer, buf: integer, comment: string}>
local current_comments = {}

local function clear_all_comments()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    end
  end
  current_comments = {}
end

local function parse_references_for_virt_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local refs = {}
  local comment_lines = {}

  for _, line in ipairs(lines) do
    -- Skip ID markers but don't exclude the comment
    if line:match("^<!%-%- ghreview:[%d.]+ %-%->$") then
      -- Skip this line, don't add to comment_lines
    elseif line == "---" then
      comment_lines = {}
    else
      local filepath, start_line = line:match("^(.+):(%d+)-%d+:$")
      if filepath then
        local abs_path = vim.fn.fnamemodify(filepath, ":p")
        local line_num = tonumber(start_line)
        local key = abs_path .. ":" .. line_num
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
          comment_lines[i] = "┇ " .. l
        end
        local comment = table.concat(comment_lines, "\n")

        refs[key] = {
          filepath = abs_path,
          line = line_num,
          comment = comment,
        }
        comment_lines = {}
      else
        table.insert(comment_lines, line)
      end
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

local function on_buffer_change(buf)
  local refs = parse_references_for_virt_text(buf)
  reconcile_comments(refs)
end

--- Create a new buffer (does not fetch existing comments)
local function create_buffer()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, BUFFER_NAME)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.keymap.set("n", "<leader><CR>", "<cmd>GHSubmit<CR>", { buffer = buf, desc = "Submit GitHub Review" })

  -- Attach to buffer for change tracking (virtual text)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          on_buffer_change(buf)
        end
      end)
    end,
    on_detach = function()
      clear_all_comments()
    end,
  })

  return buf
end

--- Get existing buffer or nil
local function get_buffer()
  local buf = vim.fn.bufnr(BUFFER_NAME)
  return buf ~= -1 and buf or nil
end

--- Get existing buffer or create new one (without fetching comments)
local function get_or_create_buffer()
  return get_buffer() or create_buffer()
end

local function get_file_path_from_repo_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 or not git_root then
    -- Fallback to relative path if not in a git repo
    return vim.fn.expand("%:.")
  end
  local file_path = vim.fn.expand("%:p")
  -- Make path relative to git root
  if file_path:sub(1, #git_root) == git_root then
    return file_path:sub(#git_root + 2) -- +2 to skip the trailing slash
  end
  return vim.fn.expand("%:.")
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

  local location = get_file_path_from_repo_root() .. ":" .. start_line .. "-" .. end_line
  return table.concat(lines, "\n"), location, start_line, end_line
end

local function build_comment(prompt, range)
  local full_prompt = prompt or ""

  if range and range > 0 then
    local selection, location, start_line, end_line = get_visual_selection()
    if selection and selection ~= "" then
      -- Format: location line, then code block (same as ccsend)
      full_prompt = full_prompt .. "\n\n" .. location .. ":\n```\n" .. selection .. "\n```"
    end
    return full_prompt, start_line, end_line
  end

  return full_prompt, nil, nil
end

--- Get PR info from current branch
---@return table|nil {number: number, commit: string, base_commit: string, owner: string, repo: string}
local function get_pr_info(callback)
  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart({ "gh", "pr", "view", "--json", "number,headRefOid,baseRefOid,url" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      stdout_data = data
    end,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local msg = table.concat(stderr_data, "\n")
        callback(nil, "Failed to get PR info: " .. msg)
        return
      end

      local json_str = table.concat(stdout_data, "\n")
      local ok, info = pcall(vim.json.decode, json_str)
      if not ok or not info then
        callback(nil, "Failed to parse PR info")
        return
      end

      -- Parse owner/repo from URL: https://github.com/owner/repo/pull/123
      local owner, repo = info.url:match("github%.com/([^/]+)/([^/]+)/pull")
      if not owner or not repo then
        callback(nil, "Failed to parse owner/repo from URL")
        return
      end

      callback({
        number = info.number,
        commit = info.headRefOid,
        base_commit = info.baseRefOid,
        owner = owner,
        repo = repo,
      })
    end,
  })
end

--- Fetch existing PR review comments (inline comments on code)
--- Returns list of {id, body, path, line, start_line}
local function fetch_pr_comments(pr_info, callback)
  local stdout_data = {}
  local stderr_data = {}

  local api_path = string.format("repos/%s/%s/pulls/%d/comments", pr_info.owner, pr_info.repo, pr_info.number)
  vim.fn.jobstart({ "gh", "api", api_path, "--paginate" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      stdout_data = data
    end,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local msg = table.concat(stderr_data, "\n")
        callback(nil, "Failed to fetch PR comments: " .. msg)
        return
      end

      local json_str = table.concat(stdout_data, "\n")
      local ok, comments = pcall(vim.json.decode, json_str)
      if not ok or not comments then
        callback({}) -- Empty list on parse failure
        return
      end

      -- Helper to handle vim.NIL from JSON null
      local function val(v)
        return v ~= vim.NIL and v or nil
      end

      local result = {}
      for _, c in ipairs(comments) do
        local line = val(c.line) or val(c.original_line)
        table.insert(result, {
          id = c.id,
          body = c.body,
          path = c.path,
          line = line,
          start_line = val(c.start_line) or line,
          created_at = c.created_at,
        })
      end
      callback(result)
    end,
  })
end

--- Fetch general PR comments (not attached to code lines)
--- Returns list of {id, body, path=nil, line=nil, start_line=nil}
local function fetch_pr_issue_comments(pr_info, callback)
  local stdout_data = {}
  local stderr_data = {}

  local api_path = string.format("repos/%s/%s/issues/%d/comments", pr_info.owner, pr_info.repo, pr_info.number)
  vim.fn.jobstart({ "gh", "api", api_path, "--paginate" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      stdout_data = data
    end,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback({}) -- Silently return empty on failure
        return
      end

      local json_str = table.concat(stdout_data, "\n")
      local ok, comments = pcall(vim.json.decode, json_str)
      if not ok or not comments then
        callback({})
        return
      end

      local result = {}
      for _, c in ipairs(comments) do
        table.insert(result, {
          id = c.id,
          body = c.body,
          path = nil,
          line = nil,
          start_line = nil,
          created_at = c.created_at,
        })
      end
      callback(result)
    end,
  })
end

--- Parse GitHub blob URL from comment body
--- Returns filepath, start_line, end_line, body_without_url or nil
local function parse_github_blob_url(body)
  -- Match: https://github.com/user/repo/blob/sha/path/to/file#L10-L20 or #L10
  local pattern = "https://github%.com/[^/]+/[^/]+/blob/[^/]+/([^#]+)#L(%d+)%-?L?(%d*)"
  local filepath, start_line, end_line = body:match(pattern)
  if filepath then
    start_line = tonumber(start_line)
    end_line = tonumber(end_line) or start_line
    -- Remove the URL from body
    local url_pattern = "https://github%.com/[^/]+/[^/]+/blob/[^/]+/[^%s]+"
    local body_without_url = body:gsub(url_pattern, ""):gsub("%s*$", ""):gsub("^%s*", "")
    return filepath, start_line, end_line, body_without_url
  end
  return nil
end

--- Add code snippet to lines from file
local function add_code_snippet(lines, git_root, filepath, start_l, end_l)
  local file_path = git_root .. "/" .. filepath
  local ok, file_lines = pcall(vim.fn.readfile, file_path)
  if ok and file_lines and #file_lines >= end_l then
    table.insert(lines, "```")
    for line_num = start_l, end_l do
      table.insert(lines, file_lines[line_num] or "")
    end
    table.insert(lines, "```")
  end
end

--- Format existing comments for buffer display
local function format_existing_comments(comments)
  -- Get git root for resolving file paths
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1] or ""

  local lines = {}
  for i, c in ipairs(comments) do
    if i > 1 then
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, "")
    end
    -- ID marker so we skip this on submit (use tostring for large integers)
    table.insert(lines, string.format("<!-- ghreview:%s -->", tostring(c.id)))

    local body = c.body
    local filepath = c.path
    local start_l = c.start_line and tonumber(tostring(c.start_line))
    local end_l = c.line and tonumber(tostring(c.line))

    -- For general comments, try to parse GitHub blob URL
    if not filepath then
      local parsed_path, parsed_start, parsed_end, body_without_url = parse_github_blob_url(body)
      if parsed_path then
        filepath = parsed_path
        start_l = parsed_start
        end_l = parsed_end
        body = body_without_url
      end
    end

    -- Comment body
    for _, body_line in ipairs(vim.split(body, "\n")) do
      table.insert(lines, body_line)
    end

    -- File reference and code snippet
    if filepath and start_l and end_l then
      table.insert(lines, "")
      table.insert(lines, string.format("%s:%d-%d:", filepath, start_l, end_l))
      add_code_snippet(lines, git_root, filepath, start_l, end_l)
    end
  end
  return lines
end

--- Parse diff to get commentable lines
--- Returns table: {filepath -> set of line numbers}
local function parse_diff(callback)
  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart({ "gh", "pr", "diff" }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      stdout_data = data
    end,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local msg = table.concat(stderr_data, "\n")
        callback(nil, "Failed to get diff: " .. msg)
        return
      end

      local diff_lines = {}
      local current_file = nil
      local current_line = 0

      for _, line in ipairs(stdout_data) do
        -- Match file header: diff --git a/path b/path or +++ b/path
        local file = line:match("^%+%+%+ b/(.+)$")
        if file then
          current_file = file
          if not diff_lines[current_file] then
            diff_lines[current_file] = {}
          end
        end

        -- Match hunk header: @@ -old,count +new,count @@
        local new_start = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
        if new_start then
          current_line = tonumber(new_start)
        elseif current_file and current_line > 0 then
          local first_char = line:sub(1, 1)
          if first_char == " " or first_char == "+" then
            -- Context or added line - commentable on RIGHT side
            diff_lines[current_file][current_line] = true
            current_line = current_line + 1
          elseif first_char == "-" then
            -- Removed line - don't increment current_line (it's not in the new file)
          elseif first_char ~= "\\" then
            -- Not a special line, reset (shouldn't happen in well-formed diff)
          end
        end
      end

      callback(diff_lines)
    end,
  })
end

local function trim_empty_lines(lines)
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end
  while #lines > 0 and vim.trim(lines[1]) == "" do
    table.remove(lines, 1)
  end
  return lines
end

--- Parse comments from buffer (only NEW comments, skips existing ones with ID markers)
--- Format: prose, then file reference line, then code block (ignored), then ---
--- Code blocks after file reference are for user context only, not included in posted body
--- Comments starting with <!-- ghreview:ID --> are existing and skipped
--- Returns list of {body: string, filepath: string|nil, start_line: number|nil, end_line: number|nil}
local function parse_comments(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local comments = {}

  local prose_lines = {} -- Lines before file reference (the actual comment body)
  local current_file_ref = nil -- {filepath, start_line, end_line}
  local has_existing_id = false -- True if this comment section has an ID marker (skip it)

  local function flush_comment()
    trim_empty_lines(prose_lines)
    -- Only add if it's a NEW comment (no existing ID) and has content
    if not has_existing_id and #prose_lines > 0 then
      table.insert(comments, {
        body = table.concat(prose_lines, "\n"),
        filepath = current_file_ref and current_file_ref.filepath,
        start_line = current_file_ref and current_file_ref.start_line,
        end_line = current_file_ref and current_file_ref.end_line,
      })
    end
    prose_lines = {}
    current_file_ref = nil
    has_existing_id = false
  end

  for _, line in ipairs(lines) do
    -- Check for existing comment ID marker (ID can be number or large int as string)
    if line:match("^<!%-%- ghreview:[%d.]+ %-%->$") then
      has_existing_id = true
    elseif line == "---" then
      flush_comment()
    else
      -- Check for reference pattern: <file>:<start>-<end>:
      local filepath, start_line, end_line = line:match("^(.+):(%d+)-(%d+):$")
      if filepath then
        -- File reference line - save it, prose before this is the body
        current_file_ref = {
          filepath = filepath,
          start_line = tonumber(start_line),
          end_line = tonumber(end_line),
        }
      elseif current_file_ref then
        -- After file reference - skip (code block for context)
      else
        -- Prose before file reference - this is the comment body
        table.insert(prose_lines, line)
      end
    end
  end

  -- Handle remaining content
  flush_comment()

  return comments
end

--- Post inline review comment
local function post_inline_comment(pr_info, filepath, start_line, end_line, body, callback)
  local args = {
    "gh", "api",
    string.format("repos/%s/%s/pulls/%d/comments", pr_info.owner, pr_info.repo, pr_info.number),
    "-f", "body=" .. body,
    "-f", "path=" .. filepath,
    "-f", "side=RIGHT",
    "-f", "commit_id=" .. pr_info.commit,
  }

  -- Multi-line comment support
  if start_line ~= end_line then
    table.insert(args, "-F")
    table.insert(args, "start_line=" .. start_line)
    table.insert(args, "-f")
    table.insert(args, "start_side=RIGHT")
    table.insert(args, "-F")
    table.insert(args, "line=" .. end_line)
  else
    table.insert(args, "-F")
    table.insert(args, "line=" .. end_line)
  end

  local stderr_data = {}
  vim.fn.jobstart(args, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(false, table.concat(stderr_data, "\n"))
      else
        callback(true)
      end
    end,
  })
end

--- Post general PR comment
local function post_pr_comment(body, callback)
  local stderr_data = {}
  vim.fn.jobstart({ "gh", "pr", "comment", "--body", body }, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      stderr_data = data
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(false, table.concat(stderr_data, "\n"))
      else
        callback(true)
      end
    end,
  })
end

--- Check if line range is in diff
local function is_in_diff(diff_map, filepath, start_line, end_line)
  local file_diff = diff_map[filepath]
  if not file_diff then return false end

  -- Check if ALL lines in range are in the diff
  for line = start_line, end_line do
    if not file_diff[line] then
      return false
    end
  end
  return true
end

--- Submit all comments
local function submit_comments(comments, pr_info, diff_map, on_complete)
  local total = #comments
  local completed = 0
  local errors = {}

  local function check_done()
    completed = completed + 1
    if completed == total then
      on_complete(errors)
    end
  end

  for _, comment in ipairs(comments) do
    if comment.filepath and comment.start_line and comment.end_line then
      -- Comment with file reference
      if is_in_diff(diff_map, comment.filepath, comment.start_line, comment.end_line) then
        -- Post as inline comment
        post_inline_comment(pr_info, comment.filepath, comment.start_line, comment.end_line, comment.body, function(ok, err)
          if not ok then
            table.insert(errors, string.format("Inline comment on %s:%d-%d failed: %s",
              comment.filepath, comment.start_line, comment.end_line, err or "unknown error"))
          end
          check_done()
        end)
      else
        -- Post as general PR comment with link to code
        local line_anchor
        if comment.start_line == comment.end_line then
          line_anchor = string.format("L%d", comment.start_line)
        else
          line_anchor = string.format("L%d-L%d", comment.start_line, comment.end_line)
        end
        local code_link = string.format(
          "https://github.com/%s/%s/blob/%s/%s#%s",
          pr_info.owner, pr_info.repo, pr_info.base_commit, comment.filepath, line_anchor
        )
        local body = string.format("%s\n\n%s", comment.body, code_link)
        post_pr_comment(body, function(ok, err)
          if not ok then
            table.insert(errors, string.format("PR comment for %s:%d-%d failed: %s",
              comment.filepath, comment.start_line, comment.end_line, err or "unknown error"))
          end
          check_done()
        end)
      end
    else
      -- General comment without file reference
      post_pr_comment(comment.body, function(ok, err)
        if not ok then
          table.insert(errors, "General PR comment failed: " .. (err or "unknown error"))
        end
        check_done()
      end)
    end
  end
end

function M.add(prompt, opts)
  local text, _, _ = build_comment(prompt, opts and opts.range)
  if text == "" or vim.trim(text) == "" then
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

  local comments = parse_comments(buf)
  if #comments == 0 then
    vim.notify("no comments to submit", vim.log.levels.WARN)
    return
  end

  vim.notify("fetching PR info...", vim.log.levels.INFO)

  get_pr_info(function(pr_info, err)
    if err then
      vim.schedule(function()
        vim.notify(err, vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      vim.notify("parsing diff...", vim.log.levels.INFO)
    end)

    parse_diff(function(diff_map, diff_err)
      if diff_err then
        vim.schedule(function()
          vim.notify(diff_err, vim.log.levels.ERROR)
        end)
        return
      end

      vim.schedule(function()
        vim.notify(string.format("submitting %d comment(s)...", #comments), vim.log.levels.INFO)
      end)

      submit_comments(comments, pr_info, diff_map, function(errors)
        vim.schedule(function()
          if #errors > 0 then
            for _, e in ipairs(errors) do
              vim.notify(e, vim.log.levels.ERROR)
            end
            vim.notify(string.format("submitted with %d error(s)", #errors), vim.log.levels.WARN)
          else
            vim.notify(string.format("submitted %d comment(s)", #comments), vim.log.levels.INFO)
            -- Clear and delete buffer on success
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end)
      end)
    end)
  end)
end

local function show_buffer(buf)
  -- Find window with buffer or open in current window
  local win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      win = w
      break
    end
  end

  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("buffer " .. buf)
  end
end

function M.open()
  -- If buffer already exists, just show it
  local existing_buf = get_buffer()
  if existing_buf then
    show_buffer(existing_buf)
    return
  end

  -- Create new buffer and fetch existing PR comments
  local buf = create_buffer()
  show_buffer(buf)

  vim.notify("fetching PR comments...", vim.log.levels.INFO)

  get_pr_info(function(pr_info, err)
    if err then
      vim.schedule(function()
        vim.notify(err, vim.log.levels.WARN)
      end)
      return
    end

    -- Fetch both inline review comments and general PR comments in parallel
    local all_comments = {}
    local pending = 2

    local function on_fetch_done()
      pending = pending - 1
      if pending > 0 then return end

      vim.schedule(function()
        if #all_comments == 0 then
          vim.notify("no existing comments", vim.log.levels.INFO)
          return
        end

        -- Sort by created_at ascending (oldest first)
        table.sort(all_comments, function(a, b)
          return (a.created_at or "") < (b.created_at or "")
        end)

        -- Populate buffer with existing comments
        local lines = format_existing_comments(all_comments)
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modified = false
          vim.notify(string.format("loaded %d existing comment(s)", #all_comments), vim.log.levels.INFO)
        end
      end)
    end

    -- Fetch inline review comments
    fetch_pr_comments(pr_info, function(comments)
      if comments then
        for _, c in ipairs(comments) do
          table.insert(all_comments, c)
        end
      end
      on_fetch_done()
    end)

    -- Fetch general PR comments
    fetch_pr_issue_comments(pr_info, function(comments)
      if comments then
        for _, c in ipairs(comments) do
          table.insert(all_comments, c)
        end
      end
      on_fetch_done()
    end)
  end)
end

function M.goto_comment()
  local review_buf = vim.fn.bufnr(BUFFER_NAME)
  if review_buf == -1 then
    vim.notify("no " .. BUFFER_NAME .. " buffer", vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  local current_line = vim.fn.line(".")

  local lines = vim.api.nvim_buf_get_lines(review_buf, 0, -1, false)
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

  -- Find window with review buffer or open in current window
  local review_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == review_buf then
      review_win = win
      break
    end
  end

  if review_win then
    vim.api.nvim_set_current_win(review_win)
  else
    vim.cmd("buffer " .. review_buf)
  end

  vim.api.nvim_win_set_cursor(0, { target_line_nr, 0 })
end

return M
