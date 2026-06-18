-- `:checkhealth brain-rag` — verifies the CLI is installed and that its API
-- version is compatible with this plugin.

local version = require("brain-rag.version")

local M = {}

function M.check()
  local h = vim.health
  h.start("brain-rag")

  h.info("Plugin version: " .. version.PLUGIN_VERSION .. " (requires CLI api " .. version.REQUIRED_API_VERSION .. ")")

  local path = version.cli_path()
  if not path then
    h.error(
      "brain-rag CLI not found",
      { "Install it (e.g. `uv tool install --editable <brain-rag repo>` or `brain-rag setup`)",
        "or set `tags.brain_rag_cmd` to its path." }
    )
    return
  end
  h.ok("CLI found: " .. path)

  -- A short synchronous call is fine inside checkhealth.
  local out = vim.fn.system({ path, "version", "--json" })
  if vim.v.shell_error ~= 0 then
    h.error(
      "CLI did not respond to `version` (likely outdated).",
      { "Update it: `uv tool upgrade brain-rag` or reinstall." }
    )
    return
  end

  local ok, data = pcall(vim.json.decode, out)
  if not ok or type(data) ~= "table" or data.api_version == nil then
    h.error("Could not parse `brain-rag version --json` output.")
    return
  end

  h.info("CLI version: " .. tostring(data.version) .. " (api " .. tostring(data.api_version) .. ")")

  local status, msg = version.compare(data.api_version)
  if status == "ok" then
    h.ok("CLI and plugin are compatible (api " .. version.REQUIRED_API_VERSION .. ").")
  else
    h.warn(msg)
  end
end

return M
