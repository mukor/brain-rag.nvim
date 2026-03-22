-- brain-rag.nvim shared utilities

local M = {}

--- Check if a file path is within the vault directory.
---@param filepath string Absolute path to check
---@param vault_dir string Vault directory path
---@return boolean
function M.is_in_vault(filepath, vault_dir)
  local resolved = vim.fn.resolve(filepath)
  local vault = vim.fn.resolve(vim.fn.expand(vault_dir))
  return resolved:sub(1, #vault) == vault
end

--- Parse frontmatter from buffer lines.
--- Returns start_line, end_line (0-indexed), and parsed tags list.
---@param lines string[] Buffer lines
---@return table|nil frontmatter info or nil if no frontmatter
function M.parse_frontmatter(lines)
  if #lines == 0 or lines[1] ~= "---" then
    return nil
  end

  local end_line = nil
  for i = 2, #lines do
    if lines[i] == "---" then
      end_line = i
      break
    end
  end

  if not end_line then
    return nil
  end

  -- Find tags line and parse existing tags
  local tags_line_idx = nil
  local existing_tags = {}

  for i = 2, end_line - 1 do
    local line = lines[i]
    local tags_match = line:match("^tags:%s*%[(.-)%]")
    if tags_match then
      tags_line_idx = i
      for tag in tags_match:gmatch("([^,%s]+)") do
        existing_tags[#existing_tags + 1] = tag
      end
      break
    elseif line:match("^tags:%s*$") then
      -- Multi-line tags format: tags:\n  - tag1\n  - tag2
      tags_line_idx = i
      for j = i + 1, end_line - 1 do
        local tag = lines[j]:match("^%s+-%s+(.+)$")
        if tag then
          existing_tags[#existing_tags + 1] = tag:match("^%s*(.-)%s*$")
        else
          break
        end
      end
      break
    end
  end

  return {
    start_line = 1,
    end_line = end_line,
    tags_line_idx = tags_line_idx,
    tags = existing_tags,
  }
end

--- Extract inline #tags from note body lines, skipping frontmatter and code blocks.
---@param lines string[] Buffer lines
---@param fm_end_line number 1-indexed end of frontmatter
---@return string[] unique tags found
function M.extract_inline_tags(lines, fm_end_line)
  local tags = {}
  local seen = {}
  local in_code_block = false

  for i = fm_end_line + 1, #lines do
    local line = lines[i]

    -- Toggle code block state
    if line:match("^```") then
      in_code_block = not in_code_block
    end

    if not in_code_block then
      -- Skip markdown headings
      if not line:match("^#+ ") then
        -- Find all #tag patterns (require leading letter, allow word chars and hyphens)
        for tag in line:gmatch("#(%a[%w_-]*)") do
          if not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
          end
        end
      end
    end
  end

  return tags
end

--- Append a wiki-link entry to today's daily note under the # Log heading.
--- Creates the daily note with frontmatter if it doesn't exist.
---@param vault_dir string Path to vault directory
---@param note_filename string Filename of the note to link (without .md)
---@param note_title string Display title for the link
function M.append_to_daily_log(vault_dir, note_filename, note_title)
  local today_str = os.date("%Y-%m-%d")
  local daily_path = vim.fn.expand(vault_dir) .. "/" .. today_str .. ".md"

  -- Create daily note if it doesn't exist
  if vim.fn.filereadable(daily_path) == 0 then
    local template = table.concat({
      "---",
      'title: "Daily - ' .. today_str .. '"',
      "date: " .. today_str,
      "tags: [daily]",
      "type: daily",
      "status: active",
      "---",
      "",
      "# Log",
      "",
    }, "\n")
    vim.fn.writefile(vim.split(template, "\n"), daily_path)
  end

  local lines = vim.fn.readfile(daily_path)

  -- Find the # Log heading
  local log_idx = nil
  for i, line in ipairs(lines) do
    if line:match("^# Log") then
      log_idx = i
      break
    end
  end

  -- Build the link entry
  local entry = "- [[" .. note_filename .. "]] - " .. note_title

  -- Check for duplicate
  for _, line in ipairs(lines) do
    if line == entry then
      return
    end
  end

  if log_idx then
    -- Insert after # Log heading (and any blank line after it)
    local insert_at = log_idx + 1
    if insert_at <= #lines and lines[insert_at] == "" then
      insert_at = insert_at + 1
    end
    table.insert(lines, insert_at, entry)
  else
    -- No # Log heading — append at end
    table.insert(lines, "")
    table.insert(lines, entry)
  end

  vim.fn.writefile(lines, daily_path)
end

--- Slugify a string for use as a filename.
---@param str string
---@return string
function M.slugify(str)
  local slug = str:lower()
  slug = slug:gsub("[^%w%s-]", "")
  slug = slug:gsub("[%s_]+", "-")
  slug = slug:gsub("^-+", ""):gsub("-+$", "")
  return slug
end

--- Create a meeting note from the current line in a daily log.
--- Replaces the line with a wiki-link and opens the new note.
---@param vault_dir string Path to vault directory
function M.create_meeting_from_line(vault_dir)
  local line = vim.api.nvim_get_current_line()
  local title = line:match("^%s*-%s*(.+)$") or line:match("^%s*(.+)$")

  if not title or title:match("^%s*$") then
    vim.notify("Empty line — type a meeting title first", vim.log.levels.WARN)
    return
  end

  -- Strip leading/trailing whitespace
  title = title:match("^%s*(.-)%s*$")

  local today_str = os.date("%Y-%m-%d")
  local slug = M.slugify(title)
  local filename = today_str .. "-" .. slug
  local filepath = vim.fn.expand(vault_dir) .. "/" .. filename .. ".md"

  -- Check if file already exists
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("Note already exists, opening: " .. filename .. ".md", vim.log.levels.INFO)
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    return
  end

  local full_title = today_str .. " - " .. title

  -- Build meeting note content
  local content = table.concat({
    "---",
    'title: "' .. full_title .. '"',
    "date: " .. today_str,
    "tags: [meeting]",
    "type: meeting",
    'summary: ""',
    'daily: "[[' .. today_str .. ']]"',
    "---",
    "",
    "# Attendees",
    "",
    "",
    "# Notes",
    "",
    "",
  }, "\n")

  vim.fn.writefile(vim.split(content, "\n"), filepath)

  -- Replace current line with wiki-link
  local link = "- [[" .. filename .. "]] - " .. title
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { link })

  -- Save the daily note, then open meeting note
  vim.cmd("write")
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

return M
