-- brain-rag.nvim configuration

local M = {}

M.defaults = {
  vault_dir = vim.fn.expand("~/notes"),

  tags = {
    enable = true,
    mode = "live", -- "live" (subprocess) or "static" (read tags.json)
    json_path = vim.fn.expand("~/.local/share/brain-rag/tags.json"),
    cache_ttl = 60, -- seconds before re-fetching tags
    brain_rag_cmd = "brain-rag", -- CLI command (allows venv path override)
  },

  snippets = {
    enable = true,
    types = { "concept", "reference", "project", "daily", "meeting", "snippet", "note" },
  },

  tag_sync = {
    enable = true,
  },

  summarize = {
    enable = true,
    model = nil, -- Ollama model for :BrainRagSummarize (nil = summary_model in brain-rag's config.yaml)
    keymap = "<leader>zs", -- set to false to skip the mapping
  },
}

local _config = {}

function M.set(opts)
  _config = opts
end

function M.get()
  return _config
end

return M
