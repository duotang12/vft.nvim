local rules = require("vft.rules")
local store = require("vft.store")

local M = {}

local config = {}
local last_fired = {} -- rule_id -> timestamp (ms) for cooldown
local notify_fn = nil -- set by init.lua to avoid circular require
local cooldown_ms = 30000 -- default 30s

--- Initialize the analyzer with user config.
--- @param opts table The full plugin config
function M.setup(opts)
  config = opts or {}
  cooldown_ms = ((opts.notify and opts.notify.cooldown) or 30) * 1000

  -- Load rules from directories
  rules.load_all(opts.custom_rules_dir)

  -- Apply per-rule enabled/disabled from config
  local rules_config = opts.rules or {}
  for id, rc in pairs(rules_config) do
    if rc.enabled == false then
      rules.disable(id)
    end
  end
end

--- Set the notification callback.
--- @param fn function(rule: table, match: table)
function M.set_notifier(fn)
  notify_fn = fn
end

--- Compute and update today's efficiency score.
--- Score = 100 - (antipattern_count / total_motions * 100), clamped 0..100.
function M.update_efficiency()
  local day = store.today()
  local total_motions = 0
  for _, count in pairs(day.motions) do
    total_motions = total_motions + count
  end
  local total_ap = 0
  for _, count in pairs(day.antipatterns) do
    total_ap = total_ap + count
  end
  if total_motions == 0 then
    store.set_efficiency_score(100)
    return
  end
  -- Each antipattern occurrence counts as 5 "wasted" motions
  local waste = total_ap * 5
  local score = 100 - (waste / total_motions) * 100
  store.set_efficiency_score(score)
end

-- Severity priority: higher = more important, gets shown over lower
local SEVERITY_PRIORITY = { warning = 3, coach = 2, hint = 1 }

local MAX_ENTRY_AGE_MS = 10000 -- ignore keystrokes older than 10 seconds

--- Filter entries to only include recent ones.
--- @param entries table[]
--- @param now number
--- @return table[]
local function filter_fresh(entries, now)
  local fresh = {}
  for _, e in ipairs(entries) do
    if (now - e.time) <= MAX_ENTRY_AGE_MS then
      fresh[#fresh + 1] = e
    end
  end
  return fresh
end

--- Run all enabled rules against the keystroke buffer.
--- Only the highest-priority match gets shown as a notification.
--- All matches still get recorded for stats/XP.
--- @param entries table[] Recent keystroke buffer entries
function M.analyze(entries)
  if #entries == 0 then return end

  local now = vim.loop.now()

  -- Drop stale entries so we never react to old keystrokes
  entries = filter_fresh(entries, now)
  if #entries == 0 then return end
  local rules_config = config.rules or {}
  local gamification = config.gamification or {}

  local best_rule = nil
  local best_match = nil
  local best_priority = 0

  for _, rule in ipairs(rules.get_enabled()) do
    -- Check cooldown
    if last_fired[rule.id] and (now - last_fired[rule.id]) < cooldown_ms then
      goto continue
    end

    -- Run detection
    local rc = rules_config[rule.id]
    local match = rule.detect(entries, rc)
    if match then
      -- Always record stats and XP
      store.record_antipattern(rule.id)
      if gamification.enabled ~= false then
        local penalty = gamification.xp_penalty_per_antipattern or 5
        store.add_xp(-penalty)
      end
      last_fired[rule.id] = now

      -- Track the highest-priority match for notification
      local pri = SEVERITY_PRIORITY[rule.severity] or 1
      if pri > best_priority then
        best_priority = pri
        best_rule = rule
        best_match = match
      end
    end

    ::continue::
  end

  -- Only notify for the single most important match
  if best_rule and notify_fn then
    M.update_efficiency()
    notify_fn(best_rule, best_match)
  end
end

--- Reward XP for efficient motions (called from tracker or externally).
--- @param key string The motion key
function M.reward_efficient(key)
  local gamification = config.gamification or {}
  if gamification.enabled == false then return end

  local efficient_keys = {
    ["{"] = true, ["}"] = true,
    ["f"] = true, ["F"] = true, ["t"] = true, ["T"] = true,
    ["/"] = true, ["?"] = true,
    ["G"] = true, ["^"] = true, ["$"] = true, ["0"] = true,
  }
  if efficient_keys[key] then
    local xp = gamification.xp_per_efficient_motion or 1
    store.add_xp(xp)
  end
end

return M
