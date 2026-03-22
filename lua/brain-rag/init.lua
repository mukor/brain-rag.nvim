-- brain-rag.nvim — Neovim integration for brain-rag vault

local config = require("brain-rag.config")

local M = {}

local function setup_cmp()
  local ok_cmp, cmp = pcall(require, "cmp")
  if not ok_cmp then
    return
  end

  local cmp_source = require("brain-rag.cmp_source")
  cmp.register_source("brain_rag", cmp_source.new())

  -- Add brain_rag to global sources (is_available() restricts to markdown)
  local current = cmp.get_config().sources or {}

  -- Avoid duplicates if setup runs twice
  for _, s in ipairs(current) do
    if s.name == "brain_rag" then
      return
    end
  end

  local sources = vim.deepcopy(current)
  table.insert(sources, { name = "brain_rag" })
  cmp.setup({ sources = sources })
end

function M.setup(opts)
  config.set(vim.tbl_deep_extend("force", config.defaults, opts or {}))

  local cfg = config.get()

  if cfg.tags.enable then
    -- Defer cmp registration: wait for InsertEnter + tick so NvChad's cmp fully loads first
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = vim.api.nvim_create_augroup("BrainRagCmp", { clear = true }),
      pattern = "*.md",
      once = true,
      callback = function()
        vim.defer_fn(function()
          setup_cmp()
          -- Preload tag cache so first completion is instant
          require("brain-rag.cmp_source").preload()
        end, 100)
      end,
    })
  end

  if cfg.snippets.enable then
    require("brain-rag.snippets").register()
  end

  if cfg.tag_sync.enable then
    require("brain-rag.tag_sync").setup()
  end

  -- Keybinding: create meeting note from current line in daily log
  vim.keymap.set("n", "<leader>zm", function()
    require("brain-rag.util").create_meeting_from_line(cfg.vault_dir)
  end, { desc = "Create meeting note from line" })
end

return M
