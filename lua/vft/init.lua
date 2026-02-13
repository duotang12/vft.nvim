--- vft.nvim - Vim Fitness Tracker
--- Entry point, setup(), and public API.

local M = {}

local DEFAULT_CONFIG = {
  enabled = true,
  notify = {
    enabled = true,
    position = "top_right",
    timeout = 3000,
    cooldown = 30,
  },
  rules = {
    -- Per-rule overrides: spam_j = { enabled = true, threshold = 4 }, etc.
  },
  gamification = {
    enabled = true,
    xp_per_efficient_motion = 1,
    xp_penalty_per_antipattern = 5,
  },
  dashboard = {
    width = 60,
    height = 30,
  },
  custom_rules_dir = nil, -- path to a directory of custom rule .lua files
  custom_achievements_dir = nil, -- path to a directory of custom achievement .lua files
}

local config = {}
local initialized = false

--- Main setup function. Call this from your plugin config.
--- @param opts table|nil User configuration (merged with defaults)
function M.setup(opts)
  if initialized then return end
  initialized = true

  local utils = require("vft.utils")
  config = utils.deep_merge(DEFAULT_CONFIG, opts or {})

  -- Initialize modules
  local store = require("vft.store")
  local tracker = require("vft.tracker")
  local analyzer = require("vft.analyzer")
  local notify = require("vft.notify")
  local dashboard = require("vft.dashboard")

  store.load()
  store.start_autosave()

  -- Load achievements
  local achievements = require("vft.achievements")
  achievements.load_all(config.custom_achievements_dir)

  notify.setup(config.notify)
  analyzer.setup(config)
  dashboard.setup(config.dashboard)

  -- Wire up analyzer as the notification callback
  analyzer.set_notifier(function(rule, match)
    notify.show(rule, match)
  end)

  -- Wire up tracker -> analyzer
  tracker.set_analyzer(function(entries)
    analyzer.analyze(entries)
  end)

  -- Start tracking if enabled
  if config.enabled then
    tracker.start()
  end

  -- Register commands
  M._register_commands()

  -- Autocmds for persistence
  local group = vim.api.nvim_create_augroup("VFT", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("vft.achievements").check_all(store)
      analyzer.update_efficiency()
      store.save()
      store.stop_autosave()
      tracker.stop()
    end,
  })

  -- Periodic achievement check (every 60s) so they can trigger mid-session
  local ach_timer = vim.loop.new_timer()
  ach_timer:start(60000, 60000, vim.schedule_wrap(function()
    require("vft.achievements").check_all(store)
  end))
end

--- Register user commands.
function M._register_commands()
  vim.api.nvim_create_user_command("VFT", function()
    require("vft.dashboard").open()
  end, { desc = "Open VFT dashboard" })

  vim.api.nvim_create_user_command("VFTStats", function()
    require("vft.dashboard").print_stats()
  end, { desc = "Print VFT stats summary" })

  vim.api.nvim_create_user_command("VFTReset", function()
    vim.ui.input({ prompt = "Reset all VFT data? Type YES to confirm: " }, function(input)
      if input == "YES" then
        require("vft.store").reset()
        vim.notify("VFT data has been reset.", vim.log.levels.WARN, { title = "VFT" })
      else
        vim.notify("Reset cancelled.", vim.log.levels.INFO, { title = "VFT" })
      end
    end)
  end, { desc = "Reset all VFT data" })

  vim.api.nvim_create_user_command("VFTEnable", function()
    local tracker = require("vft.tracker")
    if not tracker.is_running() then
      tracker.start()
      vim.notify("VFT tracking enabled.", vim.log.levels.INFO, { title = "VFT" })
    end
  end, { desc = "Enable VFT tracking" })

  vim.api.nvim_create_user_command("VFTDisable", function()
    local tracker = require("vft.tracker")
    if tracker.is_running() then
      tracker.stop()
      vim.notify("VFT tracking disabled.", vim.log.levels.INFO, { title = "VFT" })
    end
  end, { desc = "Disable VFT tracking" })

  vim.api.nvim_create_user_command("VFTRules", function(args)
    local rules = require("vft.rules")
    -- :VFTRules toggle <id> - toggle a rule
    if args.args ~= "" then
      local action, id = args.args:match("^(%S+)%s+(%S+)$")
      if action == "enable" and id then
        rules.enable(id)
        vim.notify("VFT: enabled rule '" .. id .. "'", vim.log.levels.INFO, { title = "VFT" })
        return
      elseif action == "disable" and id then
        rules.disable(id)
        vim.notify("VFT: disabled rule '" .. id .. "'", vim.log.levels.INFO, { title = "VFT" })
        return
      elseif action == "toggle" and id then
        local enabled = rules.toggle(id)
        local state = enabled and "enabled" or "disabled"
        vim.notify("VFT: " .. state .. " rule '" .. id .. "'", vim.log.levels.INFO, { title = "VFT" })
        return
      end
    end

    -- No args: list all rules with status
    local list = rules.list_all()
    local lines = { "VFT Rules", "" }
    for _, r in ipairs(list) do
      local icon = r.enabled and "\u{2705}" or "\u{274c}"
      lines[#lines + 1] = ("  %s %-25s [%s] %s"):format(icon, r.id, r.severity, r.name)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  Usage: :VFTRules enable|disable|toggle <rule_id>"
    vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})
  end, {
    desc = "List or toggle VFT rules",
    nargs = "?",
    complete = function(arglead, cmdline, _)
      local rules = require("vft.rules")
      local parts = vim.split(cmdline, "%s+")
      -- Complete action
      if #parts <= 2 then
        return vim.tbl_filter(function(s)
          return s:find(arglead, 1, true) == 1
        end, { "enable", "disable", "toggle" })
      end
      -- Complete rule id
      local ids = {}
      for _, r in ipairs(rules.list_all()) do
        if r.id:find(arglead, 1, true) == 1 then
          ids[#ids + 1] = r.id
        end
      end
      return ids
    end,
  })

  vim.api.nvim_create_user_command("VFTAchievements", function()
    local achievements = require("vft.achievements")
    local s = require("vft.store")
    local list = achievements.list(s)
    local lines = { "VFT Achievements", "" }
    for _, a in ipairs(list) do
      local status = a.earned and "\u{2705}" or "\u{2b1c}"
      lines[#lines + 1] = ("  %s %s %s - %s"):format(status, a.icon, a.name, a.description)
    end
    vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, true, {})
  end, { desc = "Show VFT achievements" })
end

--- Public API: check if tracking is active.
function M.is_enabled()
  return require("vft.tracker").is_running()
end

--- Public API: get today's data.
function M.today()
  return require("vft.store").today()
end

--- Public API: get all data.
function M.data()
  return require("vft.store").get_data()
end

return M
