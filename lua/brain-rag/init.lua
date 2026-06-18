-- brain-rag.nvim — Neovim integration for brain-rag vault

local config = require("brain-rag.config")

local M = {}

--- Insert daily-note frontmatter into an empty YYYY-MM-DD.md buffer.
local function try_insert_daily_frontmatter(buf, filepath, vault_prefix)
  if filepath:sub(1, #vault_prefix) ~= vault_prefix then
    return
  end
  local date_str = vim.fn.fnamemodify(filepath, ":t:r")
  if not date_str:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    if line ~= "" then
      return
    end
  end

  local template = {
    "---",
    'title: "Daily - ' .. date_str .. '"',
    "date: " .. date_str,
    "tags: [daily]",
    "type: daily",
    "status: active",
    "---",
    "",
    "# Log",
    "",
    "",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, template)
  if buf == vim.api.nvim_get_current_buf() then
    vim.api.nvim_win_set_cursor(0, { #template, 0 })
  end
end

local function setup_daily_autofrontmatter(vault_dir)
  local vault_prefix = vim.fn.expand(vault_dir) .. "/"

  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
    group = vim.api.nvim_create_augroup("BrainRagDailyFrontmatter", { clear = true }),
    pattern = vault_prefix .. "*.md",
    callback = function(args)
      try_insert_daily_frontmatter(args.buf, args.file, vault_prefix)
    end,
  })

  -- Lazy-loading via `ft = "markdown"` means BufReadPost already fired for the
  -- buffer that triggered plugin load. Handle currently-loaded vault buffers.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        try_insert_daily_frontmatter(buf, name, vault_prefix)
      end
    end
  end
end

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

  -- Verify the CLI's API version matches what this plugin speaks. Async +
  -- deferred so it never blocks startup; warns once on a real mismatch.
  -- Run `:checkhealth brain-rag` for full detail.
  vim.defer_fn(function()
    require("brain-rag.version").check()
  end, 200)

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
    setup_daily_autofrontmatter(cfg.vault_dir)
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
