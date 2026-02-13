local M = {}

--- Get today's date as YYYY-MM-DD string.
function M.today()
  return os.date("%Y-%m-%d")
end

--- Get current timestamp in milliseconds.
function M.now_ms()
  return vim.loop.now()
end

--- Get current hour (0-23).
function M.current_hour()
  return tonumber(os.date("%H"))
end

--- Deep merge two tables. Values from `override` take priority.
--- @param base table
--- @param override table
--- @return table
function M.deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = M.deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

--- Clamp a number between min and max.
function M.clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

--- Right-pad a string to a given width.
function M.pad_right(str, width)
  if #str >= width then return str end
  return str .. string.rep(" ", width - #str)
end

--- Left-pad a string to a given width.
function M.pad_left(str, width)
  if #str >= width then return str end
  return string.rep(" ", width - #str) .. str
end

--- Center a string within a given width.
function M.center(str, width)
  if #str >= width then return str end
  local pad = width - #str
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. str .. string.rep(" ", right)
end

--- Build a simple horizontal bar using block characters.
--- @param value number Current value
--- @param max_value number Maximum value (for scaling)
--- @param width number Character width of the bar
--- @return string
function M.bar(value, max_value, width)
  if max_value == 0 then return string.rep(" ", width) end
  local blocks = { " ", "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}" }
  local filled = (value / max_value) * width
  local full = math.floor(filled)
  local frac = filled - full
  local result = string.rep("\u{2588}", full)
  if full < width then
    local idx = math.floor(frac * 8) + 1
    result = result .. blocks[idx]
    result = result .. string.rep(" ", width - full - 1)
  end
  return result
end

--- Build a sparkline string from a list of numbers.
--- @param values number[]
--- @return string
function M.sparkline(values)
  if #values == 0 then return "" end
  local ticks = { "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}" }
  local lo = math.huge
  local hi = -math.huge
  for _, v in ipairs(values) do
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  local range = hi - lo
  local parts = {}
  for _, v in ipairs(values) do
    local idx
    if range == 0 then
      idx = 4
    else
      idx = math.floor(((v - lo) / range) * 7) + 1
    end
    parts[#parts + 1] = ticks[idx]
  end
  return table.concat(parts)
end

return M
