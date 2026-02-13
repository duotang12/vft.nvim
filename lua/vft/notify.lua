--- Real-time floating window notifications for vft.nvim.

local M = {}

local ns = vim.api.nvim_create_namespace("vft_notify")
local config = {}
local active_win = nil
local dismiss_timer = nil

-- Highlight groups (defined once, user-overridable)
local hl_defined = false
local function ensure_highlights()
  if hl_defined then return end
  hl_defined = true

  -- Only set if not already defined by user's colorscheme
  local function safe_hl(name, opts)
    local ok, existing = pcall(vim.api.nvim_get_hl_by_name, name, true)
    if not ok or (not existing.foreground and not existing.background) then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  safe_hl("VFTHint", { fg = "#7aa2f7", bg = "#1a1b26", italic = true })
  safe_hl("VFTWarning", { fg = "#e0af68", bg = "#1a1b26", bold = true })
  safe_hl("VFTCoach", { fg = "#9ece6a", bg = "#1a1b26", italic = true })
  safe_hl("VFTBorder", { fg = "#565f89", bg = "#1a1b26" })
  safe_hl("VFTTitle", { fg = "#bb9af7", bg = "#1a1b26", bold = true })
end

--- Close the active notification window if any.
local function close_active()
  if dismiss_timer then
    dismiss_timer:stop()
    dismiss_timer:close()
    dismiss_timer = nil
  end
  if active_win and vim.api.nvim_win_is_valid(active_win) then
    pcall(vim.api.nvim_win_close, active_win, true)
  end
  active_win = nil
end

--- Calculate window position based on config.
--- @param width number
--- @param height number
--- @return number row, number col
local function calc_position(width, height)
  local pos = config.position or "top_right"
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local editor_w = ui.width
  local editor_h = ui.height

  if pos == "top_right" then
    return 1, editor_w - width - 2
  elseif pos == "bottom_right" then
    return editor_h - height - 3, editor_w - width - 2
  elseif pos == "cursor" then
    local cursor = vim.api.nvim_win_get_cursor(0)
    return cursor[1], cursor[2] + 2
  else
    return 1, editor_w - width - 2
  end
end

--- Initialize the notify module.
--- @param opts table notify config subtable
function M.setup(opts)
  config = opts or {}
  ensure_highlights()
end

--- Show a notification for a triggered rule.
--- @param rule table The rule that fired
--- @param _match table The match data from detect()
function M.show(rule, _match)
  if config.enabled == false then return end

  -- Close any existing notification
  close_active()

  ensure_highlights()

  -- Build content lines
  local severity_icon = {
    hint = " Hint",
    warning = " Warning",
    coach = " Coach",
  }

  local header = severity_icon[rule.severity] or " VFT"
  local FIXED_WIDTH = 48 -- consistent notification width
  local inner = FIXED_WIDTH - 4 -- padding on each side

  -- Word-wrap a string into lines that fit within inner width
  local function wrap(text, w)
    local result = {}
    local line = ""
    for word in text:gmatch("%S+") do
      if #line == 0 then
        line = word
      elseif #line + 1 + #word <= w then
        line = line .. " " .. word
      else
        result[#result + 1] = line
        line = word
      end
    end
    if #line > 0 then result[#result + 1] = line end
    return result
  end

  -- Pad line to fixed width
  local function pad(text)
    if #text >= FIXED_WIDTH then return text end
    return text .. string.rep(" ", FIXED_WIDTH - #text)
  end

  local lines = { pad(" " .. header .. ": " .. rule.name) }
  local wrapped = wrap(rule.suggestion, inner)
  for _, wl in ipairs(wrapped) do
    lines[#lines + 1] = pad(" " .. wl)
  end

  local width = FIXED_WIDTH
  local height = #lines

  -- Window position
  local row, col = calc_position(width, height)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Apply highlights
  local hl_map = {
    hint = "VFTHint",
    warning = "VFTWarning",
    coach = "VFTCoach",
  }
  local hl = hl_map[rule.severity] or "VFTHint"
  vim.api.nvim_buf_add_highlight(buf, ns, "VFTTitle", 0, 0, -1)
  for i = 1, #lines - 1 do
    vim.api.nvim_buf_add_highlight(buf, ns, hl, i, 0, -1)
  end

  -- Open floating window
  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    zindex = 150,
  }

  local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
  if not ok then return end
  active_win = win

  -- Style the window
  pcall(vim.api.nvim_win_set_option, win, "winblend", 10)

  -- Auto-dismiss
  local timeout = config.timeout or 3000
  dismiss_timer = vim.loop.new_timer()
  dismiss_timer:start(timeout, 0, vim.schedule_wrap(function()
    close_active()
  end))
end

return M
