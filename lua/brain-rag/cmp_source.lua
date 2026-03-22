-- brain-rag.nvim nvim-cmp source for tag autocomplete

local config = require("brain-rag.config")

local source = {}
source.__index = source

-- In-memory tag cache
local cache = {
  tags = {},
  last_fetched = 0,
}

function source.new()
  return setmetatable({}, source)
end

function source:get_trigger_characters()
  return { "#" }
end

function source:is_available()
  local ft = vim.bo.filetype
  return ft == "markdown" or ft == "telekasten"
end

--- Load tags synchronously (used for preload during setup).
local function fetch_sync(cfg)
  local result = vim.fn.system(cfg.tags.brain_rag_cmd .. " tags --json")
  if vim.v.shell_error == 0 and result ~= "" then
    local ok, data = pcall(vim.json.decode, result)
    if ok and type(data) == "table" then
      cache.tags = data
      cache.last_fetched = vim.uv.now()
    end
  end
end

--- Load tags from JSON file synchronously.
local function fetch_static_sync(cfg)
  local path = vim.fn.expand(cfg.tags.json_path)
  local ok, content = pcall(vim.fn.readfile, path)
  if ok and #content > 0 then
    local parse_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
    if parse_ok and type(data) == "table" then
      cache.tags = data
      cache.last_fetched = vim.uv.now()
    end
  end
end

--- Fetch tags async via subprocess (live mode).
local function fetch_live_async(cfg, callback)
  vim.system(
    { cfg.tags.brain_rag_cmd, "tags", "--json" },
    { text = true },
    vim.schedule_wrap(function(obj)
      if obj.code == 0 and obj.stdout and obj.stdout ~= "" then
        local ok, data = pcall(vim.json.decode, obj.stdout)
        if ok and type(data) == "table" then
          cache.tags = data
          cache.last_fetched = vim.uv.now()
        end
      end
      if callback then
        callback()
      end
    end)
  )
end

--- Fetch tags async from JSON file (static mode).
local function fetch_static_async(cfg, callback)
  local path = vim.fn.expand(cfg.tags.json_path)
  vim.uv.fs_open(path, "r", 438, function(err, fd)
    if err or not fd then
      if callback then
        vim.schedule(callback)
      end
      return
    end
    vim.uv.fs_fstat(fd, function(err2, stat)
      if err2 or not stat then
        vim.uv.fs_close(fd)
        if callback then
          vim.schedule(callback)
        end
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(err3, data)
        vim.uv.fs_close(fd)
        if not err3 and data then
          local ok, parsed = pcall(vim.json.decode, data)
          if ok and type(parsed) == "table" then
            cache.tags = parsed
            cache.last_fetched = vim.uv.now()
          end
        end
        if callback then
          vim.schedule(callback)
        end
      end)
    end)
  end)
end

--- Eagerly load tags into cache (called once during setup, sync is fine here).
function source.preload()
  local cfg = config.get()
  if cfg.tags.mode == "static" then
    fetch_static_sync(cfg)
  else
    fetch_sync(cfg)
  end
end

--- Build completion items from cached tags.
local function build_items()
  local items = {}
  for tag, count in pairs(cache.tags) do
    items[#items + 1] = {
      label = tag,
      filterText = tag,
      insertText = tag,
      kind = 14, -- Keyword
      documentation = tag .. " (" .. count .. " note" .. (count == 1 and "" or "s") .. ")",
      sortText = string.format("%05d", 99999 - count),
    }
  end
  return items
end

function source:complete(params, callback)
  -- If cache is fresh, return immediately
  local cfg = config.get()
  local ttl_ms = (cfg.tags.cache_ttl or 60) * 1000

  if vim.uv.now() - cache.last_fetched < ttl_ms then
    callback({ items = build_items() })
    return
  end

  -- Cache is stale — return what we have now, refresh in background
  callback({ items = build_items() })

  if cfg.tags.mode == "static" then
    fetch_static_async(cfg)
  else
    fetch_live_async(cfg)
  end
end

return source
