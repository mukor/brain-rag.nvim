-- brain-rag.nvim frontmatter template snippets

local M = {}

local function today()
  return os.date("%Y-%m-%d")
end

--- Build a frontmatter snippet for a given note type.
local function make_snippet(ls, trigger, note_type, extra_lines)
  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node
  local f = ls.function_node

  local body = {
    t({ "---", 'title: "' }),
    i(1, "Title"),
    t({ '"', "date: " }),
    f(function()
      return today()
    end),
    t({ "", "tags: [" }),
    i(2),
    t({ "]", "type: " .. note_type }),
  }

  -- Add type-specific fields
  if extra_lines then
    for _, line in ipairs(extra_lines) do
      body[#body + 1] = t({ "", line })
    end
  end

  body[#body + 1] = t({ "", "---", "", "" })
  body[#body + 1] = i(0)

  return s(trigger, body, { description = note_type .. " note frontmatter" })
end

--- Build the daily snippet which uses date as title.
local function make_daily_snippet(ls)
  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node
  local f = ls.function_node

  return s("fmdaily", {
    t({ "---", 'title: "Daily - ' }),
    f(function()
      return today()
    end),
    t({ '"', "date: " }),
    f(function()
      return today()
    end),
    t({ "", "tags: [daily" }),
    i(1),
    t({ "]", "type: daily" }),
    t({ "", "status: active", "---", "", "# Log", "", "" }),
    i(0),
  }, { description = "daily note frontmatter" })
end

--- Build the meeting snippet with date-prefixed title and sections.
--- On first save, auto-appends a wiki-link to today's daily log.
local function make_meeting_snippet(ls)
  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node
  local f = ls.function_node

  local snippet = s("fmmeeting", {
    t({ "---", 'title: "' }),
    f(function()
      return today()
    end),
    t(" - "),
    i(1, "Meeting Title"),
    t({ '"', "date: " }),
    f(function()
      return today()
    end),
    t({ "", "tags: [meeting" }),
    i(2),
    t({ "]", "type: meeting" }),
    t({ "", 'summary: ""', "daily: \"[[" }),
    f(function()
      return today()
    end),
    t({ ']]"', "---", "", "# Attendees", "", "" }),
    i(3),
    t({ "", "# Notes", "", "" }),
    i(0),
  }, {
    description = "meeting note frontmatter",
    callbacks = {
      [-1] = {
        [require("luasnip.util.events").enter] = function()
          -- Register a one-shot BufWritePost to append to daily log on first save
          vim.api.nvim_create_autocmd("BufWritePost", {
            buffer = 0,
            once = true,
            callback = function()
              local cfg = require("brain-rag.config").get()
              local util = require("brain-rag.util")
              local bufname = vim.fn.expand("%:t:r") -- filename without extension
              -- Read title from frontmatter
              local lines = vim.api.nvim_buf_get_lines(0, 0, 20, false)
              local title = "Meeting"
              for _, line in ipairs(lines) do
                local match = line:match('^title:%s*"(.-)"')
                if match then
                  title = match
                  break
                end
              end
              util.append_to_daily_log(cfg.vault_dir, bufname, title)
            end,
          })
        end,
      },
    },
  })

  return snippet
end

function M.register()
  local ok, ls = pcall(require, "luasnip")
  if not ok then
    return
  end

  local snippets = {
    make_snippet(ls, "fmconcept", "concept", { "status: draft" }),
    make_snippet(ls, "fmreference", "reference", { 'source: ""', "status: draft" }),
    make_snippet(ls, "fmproject", "project", { "status: active" }),
    make_daily_snippet(ls),
    make_meeting_snippet(ls),
    make_snippet(ls, "fmsnippet", "snippet", { "status: draft" }),
  }

  ls.add_snippets("markdown", snippets)
  ls.add_snippets("telekasten", vim.deepcopy(snippets))
end

return M
