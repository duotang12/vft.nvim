local utils = require("vft.utils")

local M = {}

local data_path = vim.fn.stdpath("data") .. "/vft.json"
local data = nil
local save_timer = nil

local DEFAULT_DATA = {
  version = 1,
  daily_stats = {},
  achievements = {},
  total_xp = 0,
  level = 1,
  streak_current = 0,
  streak_best = 0,
  last_active_date = nil,
  lifetime_motions = {}, -- cumulative motion counts across all days
  lifetime_counts = {}, -- misc cumulative counters (e.g. "count_prefix_used")
  settings = {},
}

local function default_day()
  return {
    keystrokes = 0,
    motions = {},
    antipatterns = {},
    efficiency_score = 0,
    xp_earned = 0,
    hours_active = {},
  }
end

--- Read and parse the JSON data file. Returns the parsed table or nil on error.
local function read_file()
  local f = io.open(data_path, "r")
  if not f then return nil end
  local ok, content = pcall(f.read, f, "*a")
  f:close()
  if not ok or not content or content == "" then return nil end
  local decode_ok, result = pcall(vim.json.decode, content)
  if not decode_ok then return nil end
  return result
end

--- Write the data table to disk as JSON.
local function write_file()
  if not data then return end
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then return end
  local dir = vim.fn.fnamemodify(data_path, ":h")
  vim.fn.mkdir(dir, "p")
  local f = io.open(data_path, "w")
  if not f then return end
  pcall(f.write, f, encoded)
  f:close()
end

--- Load data from disk, merging with defaults.
function M.load()
  local stored = read_file()
  if stored then
    data = utils.deep_merge(DEFAULT_DATA, stored)
  else
    data = vim.deepcopy(DEFAULT_DATA)
  end
  -- Update streak tracking
  M._update_streak()
  return data
end

--- Save data to disk immediately.
function M.save()
  write_file()
end

--- Start periodic auto-save (every 5 minutes).
function M.start_autosave()
  if save_timer then return end
  save_timer = vim.loop.new_timer()
  save_timer:start(300000, 300000, vim.schedule_wrap(function()
    M.save()
  end))
end

--- Stop the auto-save timer.
function M.stop_autosave()
  if save_timer then
    save_timer:stop()
    save_timer:close()
    save_timer = nil
  end
end

--- Get the entire data table.
function M.get_data()
  if not data then M.load() end
  return data
end

--- Get today's stats, creating the entry if it doesn't exist.
function M.today()
  if not data then M.load() end
  local key = utils.today()
  if not data.daily_stats[key] then
    data.daily_stats[key] = default_day()
  end
  return data.daily_stats[key]
end

--- Increment a keystroke counter for today.
function M.record_keystroke()
  local day = M.today()
  day.keystrokes = day.keystrokes + 1
  -- Track active hour
  local hour = tostring(utils.current_hour())
  day.hours_active[hour] = (day.hours_active[hour] or 0) + 1
end

--- Increment a motion counter for today and lifetime.
--- @param motion string The motion key (e.g. "j", "w", "ciw")
function M.record_motion(motion)
  if not data then M.load() end
  local day = M.today()
  day.motions[motion] = (day.motions[motion] or 0) + 1
  data.lifetime_motions[motion] = (data.lifetime_motions[motion] or 0) + 1
end

--- Increment a named lifetime counter.
--- @param name string Counter name (e.g. "count_prefix_used", "text_object_used")
--- @param amount number|nil Amount to add (default 1)
function M.increment_counter(name, amount)
  if not data then M.load() end
  data.lifetime_counts[name] = (data.lifetime_counts[name] or 0) + (amount or 1)
end

--- Get a lifetime counter value.
--- @param name string
--- @return number
function M.get_counter(name)
  if not data then M.load() end
  return data.lifetime_counts[name] or 0
end

--- Get a lifetime motion count.
--- @param motion string
--- @return number
function M.get_lifetime_motion(motion)
  if not data then M.load() end
  return data.lifetime_motions[motion] or 0
end

--- Record that an anti-pattern was triggered.
--- @param rule_id string
function M.record_antipattern(rule_id)
  local day = M.today()
  day.antipatterns[rule_id] = (day.antipatterns[rule_id] or 0) + 1
end

--- Add XP (clamped so total never goes below 0).
--- @param amount number Positive to reward, negative to penalize.
function M.add_xp(amount)
  if not data then M.load() end
  local day = M.today()
  day.xp_earned = day.xp_earned + amount
  data.total_xp = math.max(0, data.total_xp + amount)
  data.level = math.floor(data.total_xp / 1000) + 1
end

--- Update the usage streak based on dates.
function M._update_streak()
  local today = utils.today()
  if data.last_active_date == today then return end
  -- Check if yesterday was the last active date
  local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
  if data.last_active_date == yesterday then
    data.streak_current = data.streak_current + 1
  elseif data.last_active_date ~= nil then
    data.streak_current = 1
  else
    data.streak_current = 1
  end
  if data.streak_current > data.streak_best then
    data.streak_best = data.streak_current
  end
  data.last_active_date = today
end

--- Update today's efficiency score.
--- @param score number 0-100
function M.set_efficiency_score(score)
  local day = M.today()
  day.efficiency_score = utils.clamp(math.floor(score), 0, 100)
end

--- Get efficiency scores for the last N days.
--- @param n number
--- @return number[]
function M.get_recent_scores(n)
  if not data then M.load() end
  local scores = {}
  for i = n - 1, 0, -1 do
    local date = os.date("%Y-%m-%d", os.time() - i * 86400)
    local day = data.daily_stats[date]
    scores[#scores + 1] = day and day.efficiency_score or 0
  end
  return scores
end

--- Grant an achievement if not already earned.
--- @param id string
--- @return boolean true if newly earned
function M.grant_achievement(id)
  if not data then M.load() end
  for _, a in ipairs(data.achievements) do
    if a == id then return false end
  end
  data.achievements[#data.achievements + 1] = id
  return true
end

--- Check if an achievement has been earned.
--- @param id string
--- @return boolean
function M.has_achievement(id)
  if not data then M.load() end
  for _, a in ipairs(data.achievements) do
    if a == id then return true end
  end
  return false
end

--- Reset all data (destructive).
function M.reset()
  data = vim.deepcopy(DEFAULT_DATA)
  M.save()
end

return M
