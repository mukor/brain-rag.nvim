-- brain-rag.nvim: summarize the current note's `source` with `brain-rag summarize`.
--
-- The CLI fetches the source (web page, PDF, Markdown file, git README),
-- summarizes it with the local model and writes `summary` / `summarized` to
-- frontmatter plus a `## Summary` section. This module saves the buffer,
-- runs that in the background, and reloads the buffer when it's done.

local config = require("brain-rag.config")
local util = require("brain-rag.util")
local version = require("brain-rag.version")

local M = {}

local messages = {
  summarized = "Summarized",
  done = "Already summarized (summarize: once). Use :BrainRagSummarize! to redo it",
  unchanged = "Source unchanged since the last summary. Use :BrainRagSummarize! to redo it",
  off = "Summarizing is off for this note. Set `summarize: once` or `auto`, or use :BrainRagSummarize!",
}

--- Reload buf from disk if the user hasn't changed it since the run started.
local function reload(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].modified then
    vim.notify("brain-rag: note changed while summarizing; run :e to load the summary", vim.log.levels.WARN)
    return
  end
  local autoread = vim.bo[buf].autoread
  vim.bo[buf].autoread = true
  vim.cmd("checktime " .. buf)
  vim.bo[buf].autoread = autoread
end

--- Summarize the current buffer's note.
---@param force boolean Summarize even if the note's `summarize` mode says it's up to date
function M.run(force)
  local cfg = config.get()
  local buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(buf)

  if filepath == "" or not util.is_in_vault(filepath, cfg.vault_dir) then
    vim.notify("brain-rag: not a note in " .. cfg.vault_dir, vim.log.levels.WARN)
    return
  end

  local cli = version.cli_path()
  if not cli then
    vim.notify("brain-rag: CLI not found (see :checkhealth brain-rag)", vim.log.levels.ERROR)
    return
  end

  if vim.bo[buf].modified then
    vim.cmd("write")
  end

  local cmd = { cli, "summarize", filepath, "--json" }
  if force then
    table.insert(cmd, "--force")
  end
  local model = (cfg.summarize or {}).model
  if model and model ~= "" then
    vim.list_extend(cmd, { "--model", model })
  end

  vim.notify("brain-rag: summarizing " .. vim.fn.fnamemodify(filepath, ":t") .. "…")
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(obj)
    local ok, results = pcall(vim.json.decode, obj.stdout or "")
    local result = ok and type(results) == "table" and results[1] or nil
    if not result then
      local err = vim.trim(obj.stderr or "")
      vim.notify("brain-rag summarize failed: " .. (err ~= "" and err or "no output"), vim.log.levels.ERROR)
      return
    end

    if result.status == "error" then
      vim.notify("brain-rag: " .. result.detail, vim.log.levels.ERROR)
      return
    end

    local msg = messages[result.status] or result.status
    if result.status == "summarized" then
      msg = msg .. " (" .. result.detail .. ")"
      reload(buf)
    end
    vim.notify("brain-rag: " .. msg)
  end))
end

function M.setup()
  vim.api.nvim_create_user_command("BrainRagSummarize", function(opts)
    M.run(opts.bang)
  end, {
    bang = true,
    desc = "Summarize this note's source (! to redo it regardless of its summarize mode)",
  })

  local keymap = (config.get().summarize or {}).keymap
  if keymap and keymap ~= "" then
    vim.keymap.set("n", keymap, function()
      M.run(false)
    end, { desc = "Summarize note source (brain-rag)" })
  end
end

return M
