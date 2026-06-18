-- brain-rag.nvim version + CLI compatibility handshake.
--
-- The plugin depends on the brain-rag CLI's command/JSON contract, which the
-- CLI exposes as an integer `api_version` (see `brain-rag version --json`).
-- This module queries that value and checks it against what the plugin speaks.

local config = require("brain-rag.config")

local M = {}

M.PLUGIN_VERSION = "0.1.0"

-- CLI api_version this plugin is built against. Bump in lockstep with the
-- CLI's API_VERSION whenever the shared contract changes incompatibly.
M.REQUIRED_API_VERSION = 1

--- Resolve the configured CLI command, falling back to the default.
local function cli_cmd()
  local cfg = config.get() or {}
  local tags = cfg.tags or {}
  local cmd = tags.brain_rag_cmd
  if not cmd or cmd == "" then
    cmd = "brain-rag"
  end
  return cmd
end

--- True if the configured CLI command is runnable (on PATH or an exec path).
function M.cli_path()
  local cmd = cli_cmd()
  local resolved = vim.fn.exepath(cmd)
  if resolved ~= "" then
    return resolved
  end
  if vim.fn.executable(cmd) == 1 then
    return cmd
  end
  return nil
end

--- Query CLI version info asynchronously.
--- cb(info|nil, err) where info = { name, version, api_version }.
function M.query(cb)
  local cmd = cli_cmd()
  local ok = pcall(
    vim.system,
    { cmd, "version", "--json" },
    { text = true },
    vim.schedule_wrap(function(obj)
      if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
        cb(nil, "CLI did not report a version (it may be outdated)")
        return
      end
      local decoded, data = pcall(vim.json.decode, obj.stdout)
      if not decoded or type(data) ~= "table" or data.api_version == nil then
        cb(nil, "could not parse 'brain-rag version --json' output")
        return
      end
      cb(data, nil)
    end)
  )
  if not ok then
    vim.schedule(function()
      cb(nil, "could not run '" .. cmd .. "' (not found on PATH?)")
    end)
  end
end

--- Compare a CLI api_version against the plugin's required version.
--- Returns (status, message): status is "ok" | "cli_old" | "cli_new".
function M.compare(cli_api)
  local req = M.REQUIRED_API_VERSION
  if cli_api == req then
    return "ok", nil
  elseif cli_api < req then
    return "cli_old",
      string.format(
        "brain-rag CLI is too old (api %d; plugin needs %d). Update it: `uv tool upgrade brain-rag` (or reinstall).",
        cli_api,
        req
      )
  else
    return "cli_new",
      string.format(
        "brain-rag CLI is newer than this plugin (api %d; plugin speaks %d). Update brain-rag.nvim.",
        cli_api,
        req
      )
  end
end

local _checked = false

--- One-shot async compatibility check; warns once on mismatch.
--- Stays silent when the CLI isn't installed (no completions already hints at
--- that, and :checkhealth reports it in detail).
function M.check(opts)
  opts = opts or {}
  if _checked and not opts.force then
    return
  end
  _checked = true

  -- Don't nag if the binary isn't installed/resolvable at all.
  if not M.cli_path() then
    return
  end

  M.query(function(info, err)
    if err then
      -- Binary exists but couldn't report a version → likely incompatible.
      vim.notify("[brain-rag] " .. err, vim.log.levels.WARN)
      return
    end
    local status, msg = M.compare(info.api_version)
    if status ~= "ok" then
      vim.notify("[brain-rag] " .. msg, vim.log.levels.WARN)
    end
  end)
end

return M
