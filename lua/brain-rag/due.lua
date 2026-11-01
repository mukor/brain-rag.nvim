-- Due dates: type "due:" and a calendar opens below the cursor.
--
-- What you type after "due:" picks the date as you go; Tab (or Enter) replaces
-- "due:…" with "📅 YYYY-MM-DD", the markup brain-rag reads as a todo's due
-- date. Esc leaves what you typed. While the calendar is open, ←/→ move a day
-- and ↑/↓ a week.
--
--   due:            today
--   due:12          2026-12-01   (a month; the current month means today)
--   due:12-12       2026-12-12   (month-day without a year: the next one to come)
--   due:2027        2027-01-01
--   due:2027-03-15  2027-03-15
--   due:+3 / +2w    3 days / 2 weeks from today
--   due:fri         next Friday (mo tu we th fr sa su, 2+ letters)
--   due:tom         tomorrow ("tod" for today)

local config = require("brain-rag.config")

local M = {}

local WEEKDAYS = { "su", "mo", "tu", "we", "th", "fr", "sa" } -- os.date wday order (1 = Sunday)
local MONTHS = {
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
}

-- Date helpers on {y, m, d} tables. Noon avoids DST edge cases.

local function time_of(date)
  return os.time({ year = date.y, month = date.m, day = date.d, hour = 12 })
end

local function from_time(t)
  local d = os.date("*t", t)
  return { y = d.year, m = d.month, d = d.day }
end

function M.add_days(date, n)
  return from_time(time_of(date) + n * 86400)
end

function M.days_in_month(y, m)
  return os.date("*t", os.time({ year = y, month = m + 1, day = 0, hour = 12 })).day
end

function M.format(date)
  return string.format("%04d-%02d-%02d", date.y, date.m, date.d)
end

local function before(a, b)
  return M.format(a) < M.format(b)
end

local function weekday(date) -- 1 = Sunday
  return os.date("*t", time_of(date)).wday
end

function M.today()
  return from_time(os.time())
end

--- The date that a query typed after "due:" means, or nil while it's
--- incomplete or invalid (the calendar then keeps showing the last good date).
---@param query string|nil
---@param today table {y, m, d}
---@return table|nil {y, m, d}
function M.parse(query, today)
  local q = vim.trim(query or ""):lower()
  if q == "" then
    return today
  end

  if #q >= 3 and ("today"):sub(1, #q) == q then
    return today
  end
  if (#q >= 3 and ("tomorrow"):sub(1, #q) == q) or q == "tmr" then
    return M.add_days(today, 1)
  end

  local n, unit = q:match("^%+(%d*)([dw]?)$")
  if n then
    local count = tonumber(n) or 0
    return M.add_days(today, unit == "w" and count * 7 or count)
  end

  if q:match("^%a%a") then
    local prefix = q:sub(1, 2)
    for wday, name in ipairs(WEEKDAYS) do
      if name == prefix then
        local ahead = (wday - weekday(today) + 7) % 7
        return M.add_days(today, ahead == 0 and 7 or ahead)
      end
    end
    return nil
  end

  if not q:match("^[%d%-]+$") then
    return nil
  end
  local parts = vim.split(q, "-", { plain = true })
  if #parts > 3 then
    return nil
  end
  local first = parts[1]

  local function month_of(text)
    if text == nil or text == "" then
      return 1
    end
    local m = tonumber(text)
    if not m or m < 1 or m > 12 then
      return nil
    end
    return m
  end

  local function day_in(y, m, text)
    local d = tonumber(text or "") or 1
    return math.max(1, math.min(d, M.days_in_month(y, m)))
  end

  if #first == 4 then
    local y = tonumber(first)
    local m = month_of(parts[2])
    if not m then
      return nil
    end
    return { y = y, m = m, d = day_in(y, m, parts[3]) }
  end

  if #first == 1 or #first == 2 then
    if #parts > 2 then
      return nil
    end
    local m = tonumber(first)
    if not m or m < 1 or m > 12 then
      return nil
    end
    if parts[2] == nil then
      -- Just a month: this month means today; an earlier one, next year's
      if m == today.m then
        return today
      end
      return { y = m < today.m and today.y + 1 or today.y, m = m, d = 1 }
    end
    local date = { y = today.y, m = m, d = day_in(today.y, m, parts[2]) }
    if before(date, today) then
      date = { y = today.y + 1, m = m, d = day_in(today.y + 1, m, parts[2]) }
    end
    return date
  end

  return nil -- e.g. 3 digits: a year on its way
end

--- Lines and highlights for a month calendar.
---@return string[] lines, table[] highlights {line, col_start, col_end, group} (0-based, bytes)
function M.calendar(target, today, week_start)
  local first_wday = week_start == "monday" and 2 or 1
  local names = week_start == "monday" and { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
    or { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
  local width = 20
  local title = MONTHS[target.m] .. " " .. target.y
  local pad = math.floor((width - #title) / 2)
  local lines = { string.rep(" ", pad) .. title, table.concat(names, " ") }
  local highlights = {
    { 0, 0, #lines[1], "Title" },
    { 1, 0, #lines[2], "Comment" },
  }

  local start = (weekday({ y = target.y, m = target.m, d = 1 }) - first_wday + 7) % 7
  local cells = {}
  for _ = 1, start do
    cells[#cells + 1] = "  "
  end
  for d = 1, M.days_in_month(target.y, target.m) do
    cells[#cells + 1] = string.format("%2d", d)
  end
  for row = 0, math.ceil(#cells / 7) - 1 do
    local week = {}
    for i = 1, 7 do
      week[i] = cells[row * 7 + i] or "  "
    end
    lines[#lines + 1] = table.concat(week, " ")
    for i = 1, 7 do
      local day = tonumber(vim.trim(week[i]))
      if day then
        local col = (i - 1) * 3
        local line = #lines - 1
        if day == target.d then
          highlights[#highlights + 1] = { line, col, col + 2, "PmenuSel" }
        elseif target.y == today.y and target.m == today.m and day == today.d then
          highlights[#highlights + 1] = { line, col, col + 2, "Underlined" }
        end
      end
    end
  end
  local hint = "⇥ " .. M.format(target)
  lines[#lines + 1] = hint
  highlights[#highlights + 1] = { #lines - 1, 0, #hint, "Comment" }
  return lines, highlights
end

--- "due:" and what follows it, ending at the cursor, if the text before the
--- cursor ends that way. "due" must not follow a letter or digit ("overdue:").
---@return integer|nil start byte where "due:" begins (0-based)
---@return string|nil query what follows "due:"
function M.match(text_before_cursor)
  local start, query = text_before_cursor:match("()due:([%w%+%-]*)$")
  if not start then
    return nil
  end
  if start > 1 and text_before_cursor:sub(start - 1, start - 1):match("[%w_]") then
    return nil
  end
  return start - 1, query
end

-- The open picker (one at a time)

---@class BrainRagDueSession
---@field buf integer
---@field row integer cursor row (1-based) when it opened
---@field start integer byte column (0-based) where "due:" begins
---@field offset integer days moved with the arrow keys
---@field query? string what follows "due:"
---@field parsed? table the date `query` means, if it means one
---@field last? table the last date a query meant (kept while one is incomplete)
---@field win? integer the calendar's floating window
---@field float_buf? integer
---@field saved_maps? table<string, table> buffer-local mappings to restore

---@type BrainRagDueSession|nil
local session = nil
local ns = vim.api.nvim_create_namespace("brain_rag_due")
local KEYS = { "<Tab>", "<CR>", "<Left>", "<Right>", "<Up>", "<Down>" }

local function settings()
  return vim.tbl_extend("force", { week_start = "sunday" }, config.get().due or {})
end

---@param s BrainRagDueSession
local function current_target(s)
  local base = s.parsed or s.last or M.today()
  return M.add_days(base, s.offset)
end

---@param s BrainRagDueSession
local function render(s)
  local target = current_target(s)
  local lines, highlights = M.calendar(target, M.today(), settings().week_start)
  if not s.float_buf or not vim.api.nvim_buf_is_valid(s.float_buf) then
    s.float_buf = vim.api.nvim_create_buf(false, true)
  end
  vim.api.nvim_buf_set_lines(s.float_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(s.float_buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(s.float_buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)[2]
  local shift = vim.fn.strdisplaywidth(line:sub(s.start + 1, cursor))
  local opts = {
    relative = "cursor",
    row = 1,
    col = -shift,
    width = 20,
    height = #lines,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 60,
  }
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_set_config(s.win, opts)
  else
    s.win = vim.api.nvim_open_win(s.float_buf, false, opts)
  end
end

---@param s BrainRagDueSession
local function restore_keys(s)
  for lhs, saved in pairs(s.saved_maps or {}) do
    pcall(vim.keymap.del, "i", lhs, { buffer = s.buf })
    if saved and not vim.tbl_isempty(saved) then
      pcall(vim.fn.mapset, "i", false, saved)
    end
  end
  s.saved_maps = nil
end

function M.close()
  if not session then
    return
  end
  if session.win and vim.api.nvim_win_is_valid(session.win) then
    vim.api.nvim_win_close(session.win, true)
  end
  if session.float_buf and vim.api.nvim_buf_is_valid(session.float_buf) then
    vim.api.nvim_buf_delete(session.float_buf, { force = true })
  end
  restore_keys(session)
  session = nil
end

--- Replace "due:…" with "📅 YYYY-MM-DD".
function M.accept()
  if not session then
    return
  end
  local date = M.format(current_target(session))
  local row, cursor = unpack(vim.api.nvim_win_get_cursor(0))
  local stamp = "📅 " .. date
  vim.api.nvim_buf_set_text(session.buf, row - 1, session.start, row - 1, cursor, { stamp })
  local start = session.start
  M.close()
  vim.api.nvim_win_set_cursor(0, { row, start + #stamp })
end

local function move(days)
  if not session then
    return
  end
  session.offset = session.offset + days
  render(session)
end

---@param s BrainRagDueSession
---@param buf integer
local function bind_keys(s, buf)
  s.saved_maps = {}
  local actions = {
    ["<Tab>"] = M.accept,
    ["<CR>"] = M.accept,
    ["<Left>"] = function() move(-1) end,
    ["<Right>"] = function() move(1) end,
    ["<Up>"] = function() move(-7) end,
    ["<Down>"] = function() move(7) end,
  }
  for _, lhs in ipairs(KEYS) do
    local existing = vim.fn.maparg(lhs, "i", false, true)
    -- Only buffer-local mappings need restoring; ours shadows global ones
    s.saved_maps[lhs] = (existing and existing.buffer == 1) and existing or {}
    vim.keymap.set("i", lhs, actions[lhs], { buffer = buf, nowait = true, desc = "brain-rag due date" })
  end
end

--- Open, update or close the picker after a change in insert mode.
function M.on_text_changed()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local start, query = M.match(vim.api.nvim_get_current_line():sub(1, col))
  if not start then
    M.close()
    return
  end
  if session and (session.buf ~= buf or session.row ~= row or session.start ~= start) then
    M.close()
  end
  if not session then
    session = { buf = buf, row = row, start = start, offset = 0 }
    bind_keys(session, buf)
  end
  if session.query ~= query then
    session.offset = 0
    session.query = query
    local parsed = M.parse(query, M.today())
    session.parsed = parsed
    if parsed then
      session.last = parsed
    end
  end
  render(session)
end

local function attach(group, buf)
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = buf,
    callback = M.on_text_changed,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    group = group,
    buffer = buf,
    callback = M.close,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("BrainRagDue", { clear = true })
  local filetypes = settings().filetypes or { "markdown", "telekasten" }
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = filetypes,
    callback = function(args)
      attach(group, args.buf)
    end,
  })
  -- Buffers already open when the plugin loaded (lazy-loading on ft=markdown)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(filetypes, vim.bo[buf].filetype) then
      attach(group, buf)
    end
  end
end

-- For tests
function M._session()
  return session
end

return M
