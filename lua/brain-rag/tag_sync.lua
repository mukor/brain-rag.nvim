-- brain-rag.nvim auto-tag sync on save

local config = require("brain-rag.config")
local util = require("brain-rag.util")

local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("BrainRagTagSync", { clear = true }),
    pattern = "*.md",
    callback = function()
      local cfg = config.get()
      local filepath = vim.fn.expand("%:p")

      -- Only sync files in the vault
      if not util.is_in_vault(filepath, cfg.vault_dir) then
        return
      end

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local fm = util.parse_frontmatter(lines)

      if not fm or not fm.tags_line_idx then
        return
      end

      local inline_tags = util.extract_inline_tags(lines, fm.end_line)

      if #inline_tags == 0 then
        return
      end

      -- Build set of existing tags for dedup
      local existing_set = {}
      for _, tag in ipairs(fm.tags) do
        existing_set[tag] = true
      end

      -- Collect new tags
      local new_tags = {}
      for _, tag in ipairs(inline_tags) do
        if not existing_set[tag] then
          new_tags[#new_tags + 1] = tag
          existing_set[tag] = true
        end
      end

      if #new_tags == 0 then
        return
      end

      -- Merge and build updated tags line
      local all_tags = {}
      for _, tag in ipairs(fm.tags) do
        all_tags[#all_tags + 1] = tag
      end
      for _, tag in ipairs(new_tags) do
        all_tags[#all_tags + 1] = tag
      end

      local updated_line = "tags: [" .. table.concat(all_tags, ", ") .. "]"

      -- Save cursor position
      local cursor = vim.api.nvim_win_get_cursor(0)

      -- Replace the tags line (0-indexed)
      vim.api.nvim_buf_set_lines(0, fm.tags_line_idx - 1, fm.tags_line_idx, false, { updated_line })

      -- Restore cursor
      pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    end,
  })
end

return M
