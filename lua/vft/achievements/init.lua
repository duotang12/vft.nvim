--- Achievement loader for vft.nvim.
--- Auto-discovers achievement files from the built-in achievements/ directory
--- and an optional user-configured custom_achievements_dir.
--- Each achievement file should return a table with: id, name, icon,
--- description, and check(store) -> boolean.

local M = {}

--- All loaded achievements, keyed by id.
--- @type table<string, table>
M.loaded = {}

--- Ordered list of achievement ids.
--- @type string[]
M.order = {}

--- Scan a directory for .lua achievement files and load them.
--- @param dir string Absolute path to directory
local function load_dir(dir)
  local handle = vim.loop.fs_scandir(dir)
  if not handle then return end

  while true do
    local name, typ = vim.loop.fs_scandir_next(handle)
    if not name then break end

    if typ == "file" and name:match("%.lua$") and name ~= "init.lua" then
      local mod_name = name:gsub("%.lua$", "")
      local achievement

      if dir:match("vft/achievements/?$") then
        -- Built-in: use require
        local mod_path = "vft.achievements." .. mod_name
        local ok, result = pcall(require, mod_path)
        if ok and type(result) == "table" and result.id then
          achievement = result
        elseif not ok then
          vim.notify("VFT: failed to load achievement " .. mod_path .. ": " .. tostring(result), vim.log.levels.WARN)
        end
      else
        -- Custom dir: dofile
        local filepath = dir .. "/" .. name
        local ok, result = pcall(dofile, filepath)
        if ok and type(result) == "table" and result.id then
          achievement = result
        elseif not ok then
          vim.notify("VFT: failed to load achievement " .. filepath .. ": " .. tostring(result), vim.log.levels.WARN)
        end
      end

      if achievement then
        M.loaded[achievement.id] = achievement
        if not vim.tbl_contains(M.order, achievement.id) then
          M.order[#M.order + 1] = achievement.id
        end
      end
    end
  end
end

--- Load all achievements from built-in directory and optional custom directory.
--- @param custom_dir string|nil
function M.load_all(custom_dir)
  M.loaded = {}
  M.order = {}

  local source = debug.getinfo(1, "S").source:sub(2)
  local builtin_dir = vim.fn.fnamemodify(source, ":h")
  load_dir(builtin_dir)

  if custom_dir then
    local expanded = vim.fn.expand(custom_dir)
    if vim.fn.isdirectory(expanded) == 1 then
      load_dir(expanded)
    end
  end
end

--- Run all achievement checks and grant any newly earned ones.
--- @param store table The store module
function M.check_all(store)
  for _, id in ipairs(M.order) do
    local achievement = M.loaded[id]
    if achievement.check and not store.has_achievement(id) then
      local earned = achievement.check(store)
      if earned then
        store.grant_achievement(id)
        M._on_earn(achievement)
      end
    end
  end
end

--- Notification when an achievement is newly earned.
--- @param achievement table
function M._on_earn(achievement)
  vim.schedule(function()
    vim.notify(
      ("Achievement Unlocked: %s %s - %s"):format(achievement.icon, achievement.name, achievement.description),
      vim.log.levels.INFO,
      { title = "VFT" }
    )
  end)
end

--- Get a list of all achievements with earned status.
--- @param store table The store module
--- @return table[]
function M.list(store)
  local result = {}
  for _, id in ipairs(M.order) do
    local a = M.loaded[id]
    result[#result + 1] = {
      id = a.id,
      name = a.name,
      icon = a.icon,
      description = a.description,
      earned = store.has_achievement(a.id),
    }
  end
  return result
end

return M
