--- Rule loader for vft.nvim.
--- Auto-discovers rule files from the built-in rules/ directory
--- and an optional user-configured custom_rules_dir.
--- Each rule file should return a table with: id, name, description,
--- severity, suggestion, and detect(entries, config).

local M = {}

--- All loaded rules, keyed by id.
--- @type table<string, table>
M.loaded = {}

--- Ordered list of rule ids (for consistent iteration).
--- @type string[]
M.order = {}

--- Set of manually disabled rule ids (runtime toggle).
--- @type table<string, boolean>
M.disabled = {}

--- Scan a directory for .lua rule files and load them.
--- Skips init.lua and helpers.lua.
--- @param dir string Absolute path to directory
local function load_dir(dir)
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return end

  while true do
    local name, typ = vim.loop.fs_scandir_next(handle)
    if not name then break end

    if typ == "file" and name:match("%.lua$") and name ~= "init.lua" and name ~= "helpers.lua" then
      local mod_name = name:gsub("%.lua$", "")
      -- Try to require the module
      local mod_path
      -- Check if this is the built-in rules dir
      if dir:match("vft/rules/?$") then
        mod_path = "vft.rules." .. mod_name
      else
        -- Custom dir: load the file directly
        local filepath = dir .. "/" .. name
        local ok, rule = pcall(dofile, filepath)
        if ok and type(rule) == "table" and rule.id and rule.detect then
          M.loaded[rule.id] = rule
          if not vim.tbl_contains(M.order, rule.id) then
            M.order[#M.order + 1] = rule.id
          end
        elseif not ok then
          vim.notify("VFT: failed to load rule " .. filepath .. ": " .. tostring(rule), vim.log.levels.WARN)
        end
        goto continue
      end

      -- Built-in: use require so it's cached properly
      -- Clear from cache first to allow reloading
      local ok, rule = pcall(require, mod_path)
      if ok and type(rule) == "table" and rule.id and rule.detect then
        M.loaded[rule.id] = rule
        if not vim.tbl_contains(M.order, rule.id) then
          M.order[#M.order + 1] = rule.id
        end
      elseif not ok then
        vim.notify("VFT: failed to load rule " .. mod_path .. ": " .. tostring(rule), vim.log.levels.WARN)
      end

      ::continue::
    end
  end
end

--- Load all rules from built-in directory and optional custom directory.
--- @param custom_dir string|nil Optional path to user's custom rules directory
function M.load_all(custom_dir)
  M.loaded = {}
  M.order = {}

  -- Find the built-in rules directory
  local source = debug.getinfo(1, "S").source:sub(2) -- remove leading @
  local builtin_dir = vim.fn.fnamemodify(source, ":h")
  load_dir(builtin_dir)

  -- Load custom rules
  if custom_dir then
    local expanded = vim.fn.expand(custom_dir)
    if vim.fn.isdirectory(expanded) == 1 then
      load_dir(expanded)
    end
  end
end

--- Get all enabled rules in order.
--- @return table[]
function M.get_enabled()
  local result = {}
  for _, id in ipairs(M.order) do
    if not M.disabled[id] then
      result[#result + 1] = M.loaded[id]
    end
  end
  return result
end

--- Get all rules with their enabled status.
--- @return table[]
function M.list_all()
  local result = {}
  for _, id in ipairs(M.order) do
    local rule = M.loaded[id]
    result[#result + 1] = {
      id = rule.id,
      name = rule.name,
      severity = rule.severity,
      enabled = not M.disabled[id],
    }
  end
  return result
end

--- Enable a rule by id.
--- @param id string
function M.enable(id)
  M.disabled[id] = nil
end

--- Disable a rule by id.
--- @param id string
function M.disable(id)
  if M.loaded[id] then
    M.disabled[id] = true
  end
end

--- Toggle a rule by id. Returns the new enabled state.
--- @param id string
--- @return boolean enabled
function M.toggle(id)
  if M.disabled[id] then
    M.disabled[id] = nil
    return true
  else
    M.disabled[id] = true
    return false
  end
end

--- Get a single rule by id.
--- @param id string
--- @return table|nil
function M.get(id)
  return M.loaded[id]
end

return M
