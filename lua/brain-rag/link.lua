-- Link a selection: select text in visual mode, press <leader>zl, then choose
--   URL…           [text](https://…)
--   New note       creates a note titled with the text (brain-rag create) and links it
--   Existing note… pick a note in the vault and link it
-- Note links are Telekasten wiki links: [[note]] when the text is the note's
-- name, else [[note|text]] (Telekasten shows the text with conceallevel=2).

local config = require("brain-rag.config")

local M = {}

--- The wiki link to a note (file name without .md) showing `text`.
function M.wiki_link(note, text)
  if note == text then
    return "[[" .. note .. "]]"
  end
  return "[[" .. note .. "|" .. text .. "]]"
end

--- A Markdown link; angle brackets keep URLs with spaces or parentheses intact.
function M.url_link(text, url)
  if url:match("[%s()]") then
    url = "<" .. url .. ">"
  end
  return "[" .. text .. "](" .. url .. ")"
end

--- The visual selection on one line: row (0-based), start and end byte columns
--- (end exclusive), and the text. nil for a selection across lines.
function M.selection(buf)
  local s = vim.api.nvim_buf_get_mark(buf, "<")
  local e = vim.api.nvim_buf_get_mark(buf, ">")
  if s[1] == 0 or s[1] ~= e[1] then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(buf, s[1] - 1, s[1], false)[1] or ""
  local last = math.min(e[2], #line - 1)
  -- The end mark is the first byte of the last character; include all of it
  local stop = last + 1 + vim.str_utf_end(line, last + 1)
  return { row = s[1] - 1, start = s[2], stop = stop, text = line:sub(s[2] + 1, stop) }
end

local function replace(buf, sel, text)
  vim.api.nvim_buf_set_text(buf, sel.row, sel.start, sel.row, sel.stop, { text })
end

--- Note names in the vault (file names without .md), most recently edited first.
function M.notes(vault)
  local files = vim.fn.globpath(vault, "**/*.md", false, true)
  table.sort(files, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)
  local names, seen = {}, {}
  for _, f in ipairs(files) do
    local name = vim.fn.fnamemodify(f, ":t:r")
    if not seen[name] and not f:find("/templates/", 1, true) then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

local function link_url(buf, sel)
  local clip = vim.fn.getreg("+")
  local default = clip:match("^https?://%S+$") and clip or ""
  vim.ui.input({ prompt = "URL: ", default = default }, function(url)
    if url and vim.trim(url) ~= "" then
      replace(buf, sel, M.url_link(sel.text, vim.trim(url)))
    end
  end)
end

local function link_existing(buf, sel)
  local vault = vim.fn.expand(config.get().vault_dir)
  vim.ui.select(M.notes(vault), { prompt = "Link to note" }, function(note)
    if note then
      replace(buf, sel, M.wiki_link(note, sel.text))
    end
  end)
end

local function link_new(buf, sel)
  local cfg = config.get()
  local types = (cfg.snippets and cfg.snippets.types) or { "note" }
  vim.ui.select(types, { prompt = "Note type for “" .. sel.text .. "”" }, function(note_type)
    if not note_type then
      return
    end
    local cmd = (cfg.tags and cfg.tags.brain_rag_cmd) or "brain-rag"
    vim.system({ cmd, "create", "--type", note_type, sel.text }, { text = true }, function(out)
      vim.schedule(function()
        local path = (out.stdout or ""):match("Created:%s*(.-%.md)%s*\n?$")
        if out.code ~= 0 or not path then
          local err = vim.trim((out.stderr ~= "" and out.stderr) or out.stdout or "")
          vim.notify("brain-rag create failed: " .. err, vim.log.levels.ERROR)
          return
        end
        replace(buf, sel, M.wiki_link(vim.fn.fnamemodify(path, ":t:r"), sel.text))
        vim.notify("Created " .. vim.fn.fnamemodify(path, ":~"))
      end)
    end)
  end)
end

function M.link_selection()
  local buf = vim.api.nvim_get_current_buf()
  local sel = M.selection(buf)
  if not sel or sel.text == "" then
    vim.notify("brain-rag: select text on one line to link it", vim.log.levels.WARN)
    return
  end
  local choices = { "URL…", "New note", "Existing note…" }
  vim.ui.select(choices, { prompt = "Link “" .. sel.text .. "” to" }, function(choice)
    if choice == choices[1] then
      link_url(buf, sel)
    elseif choice == choices[2] then
      link_new(buf, sel)
    elseif choice == choices[3] then
      link_existing(buf, sel)
    end
  end)
end

function M.setup()
  local keymap = (config.get().link or {}).keymap
  if keymap and keymap ~= "" then
    -- <Esc> first so the '< and '> marks are set for this selection
    vim.keymap.set("x", keymap, "<Esc><Cmd>lua require('brain-rag.link').link_selection()<CR>", {
      desc = "Link the selection (URL, new note, existing note)",
    })
  end
end

return M
