--- Floating window dashboard for vft.nvim.

local store = require("vft.store")
local utils = require("vft.utils")

local M = {}

local config = {}
local dash_win = nil
local dash_buf = nil

function M.setup(opts)
  config = opts or {}
end

--- Close the dashboard if open.
function M.close()
  if dash_win and vim.api.nvim_win_is_valid(dash_win) then
    pcall(vim.api.nvim_win_close, dash_win, true)
  end
  dash_win = nil
  dash_buf = nil
end

--- Check if dashboard is currently open.
function M.is_open()
  return dash_win ~= nil and vim.api.nvim_win_is_valid(dash_win)
end

--- Build the dashboard content lines.
--- @return string[]
local function build_content()
  local data = store.get_data()
  local day = store.today()
  local lines = {}

  local function add(line)
    lines[#lines + 1] = line or ""
  end

  --- Word-wrap a long line and add all resulting lines.
  --- @param text string The full line text
  --- @param indent string Indentation prefix for continuation lines
  --- @param max number Max line width
  local function add_wrapped(text, indent, max)
    if #text <= max then
      add(text)
      return
    end
    -- Wrap at word boundaries
    local remaining = text
    local first = true
    while #remaining > 0 do
      local prefix = first and "" or indent
      local line_max = max - #prefix
      if #remaining <= line_max then
        add(prefix .. remaining)
        break
      end
      -- Find last space within limit
      local cut = remaining:sub(1, line_max + 1):find("%s[^%s]*$")
      if not cut or cut < 10 then cut = line_max end
      add(prefix .. remaining:sub(1, cut - 1))
      remaining = remaining:sub(cut):match("^%s*(.*)")
      first = false
    end
  end

  local function hr(width)
    add(string.rep("\u{2500}", width))
  end

  local width = (config.width or 60) - 4 -- inner width accounting for padding

  -- Header
  add(utils.center("VFT \u{2014} Vim Fitness Tracker", width))
  add(utils.center(utils.today(), width))
  hr(width)

  -- Today's Stats
  add("")
  add("  Today's Stats")
  add("")
  add(("    Keystrokes:       %d"):format(day.keystrokes))
  add(("    Efficiency Score: %d/100"):format(day.efficiency_score))
  add(("    XP Earned Today:  %+d"):format(day.xp_earned))
  add("")

  -- Anti-patterns detected
  local ap_count = 0
  local ap_lines = {}
  for id, count in pairs(day.antipatterns) do
    ap_count = ap_count + count
    ap_lines[#ap_lines + 1] = { id = id, count = count }
  end
  table.sort(ap_lines, function(a, b) return a.count > b.count end)

  add(("    Anti-patterns:    %d total"):format(ap_count))
  for _, ap in ipairs(ap_lines) do
    local line = ("      \u{2022} %-25s %dx"):format(ap.id, ap.count)
    add_wrapped(line, "          ", width)
  end
  add("")
  hr(width)

  -- Top motions
  add("")
  add("  Most Used Motions")
  add("")

  local motion_list = {}
  local max_motion = 0
  for key, count in pairs(day.motions) do
    motion_list[#motion_list + 1] = { key = key, count = count }
    if count > max_motion then max_motion = count end
  end
  table.sort(motion_list, function(a, b) return a.count > b.count end)

  local bar_width = 20
  for i = 1, math.min(10, #motion_list) do
    local m = motion_list[i]
    local bar = utils.bar(m.count, max_motion, bar_width)
    add(("    %-4s %s %d"):format(m.key, bar, m.count))
  end

  if #motion_list == 0 then
    add("    (no motions recorded yet)")
  end

  add("")
  hr(width)

  -- 7-day trend
  add("")
  add("  7-Day Efficiency Trend")
  add("")

  local scores = store.get_recent_scores(7)
  local spark = utils.sparkline(scores)
  add("    " .. spark)

  -- Show score values
  local score_strs = {}
  for _, s in ipairs(scores) do
    score_strs[#score_strs + 1] = ("%2d"):format(s)
  end
  add("    " .. table.concat(score_strs, " "))
  add("")
  hr(width)

  -- Gamification summary
  add("")
  add("  Progress")
  add("")
  add(("    Level:          %d"):format(data.level))
  add(("    Total XP:       %d"):format(data.total_xp))

  -- XP bar to next level
  local xp_in_level = data.total_xp % 1000
  local xp_bar = utils.bar(xp_in_level, 1000, 20)
  add(("    Next Level:     %s %d/1000"):format(xp_bar, xp_in_level))
  add("")
  add(("    Current Streak: %d day(s)"):format(data.streak_current))
  add(("    Best Streak:    %d day(s)"):format(data.streak_best))
  add("")

  -- Achievements
  local ach = require("vft.achievements")
  local ach_list = ach.list(store)
  local earned_any = false
  for _, a in ipairs(ach_list) do
    if a.earned then earned_any = true break end
  end
  if earned_any then
    add("    Achievements:")
    for _, a in ipairs(ach_list) do
      if a.earned then
        local line = ("      %s %s - %s"):format(a.icon, a.name, a.description)
        add_wrapped(line, "          ", width)
      end
    end
    add("")
  end

  hr(width)
  add("")
  add(utils.center("Press q or <Esc> to close", width))

  return lines
end

--- Open the dashboard floating window.
function M.open()
  if M.is_open() then
    M.close()
    return
  end

  local lines = build_content()

  -- Create buffer
  dash_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(dash_buf, 0, -1, false, lines)
  vim.bo[dash_buf].modifiable = false
  vim.bo[dash_buf].bufhidden = "wipe"
  vim.bo[dash_buf].filetype = "vft"

  -- Calculate window size
  local width = config.width or 60
  local height = math.min(config.height or 30, #lines + 2)
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " VFT ",
    title_pos = "center",
    zindex = 100,
  }

  local ok, win = pcall(vim.api.nvim_open_win, dash_buf, true, win_opts)
  if not ok then return end
  dash_win = win

  -- Window options
  pcall(vim.api.nvim_win_set_option, win, "cursorline", true)
  pcall(vim.api.nvim_win_set_option, win, "winblend", 5)

  -- Keymaps to close
  local close_keys = { "q", "<Esc>" }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      M.close()
    end, { buffer = dash_buf, nowait = true, silent = true })
  end
end

--- Print today's stats summary to the command line.
function M.print_stats()
  local day = store.today()
  local data = store.get_data()

  local ap_total = 0
  for _, c in pairs(day.antipatterns) do
    ap_total = ap_total + c
  end

  local msg = table.concat({
    ("VFT \u{2014} %s"):format(utils.today()),
    ("  Keystrokes: %d"):format(day.keystrokes),
    ("  Efficiency: %d/100"):format(day.efficiency_score),
    ("  Anti-patterns: %d"):format(ap_total),
    ("  Level: %d | XP: %d | Streak: %d days"):format(data.level, data.total_xp, data.streak_current),
  }, "\n")

  vim.api.nvim_echo({ { msg, "Normal" } }, true, {})
end

return M
