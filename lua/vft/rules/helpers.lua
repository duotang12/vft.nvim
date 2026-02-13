--- Shared helpers for writing VFT rules.
--- Rule files can require("vft.rules.helpers") to use these.

local M = {}

--- Count consecutive identical keys at the tail of the buffer, in normal mode.
--- @param entries table[] Ring buffer entries (oldest first)
--- @param key string The key to look for
--- @return number count
function M.count_consecutive_tail(entries, key)
  local count = 0
  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.key == key and (e.mode == "n" or e.mode == "no") then
      count = count + 1
    else
      break
    end
  end
  return count
end

--- Check if a sequence of keys appears at the tail of normal-mode entries.
--- @param entries table[]
--- @param seq string[] e.g. {"d", "d", "p"}
--- @param max_gap_ms number Max time between keys
--- @return boolean
function M.tail_matches_seq(entries, seq, max_gap_ms)
  if #entries < #seq then return false end
  local start = #entries - #seq + 1
  for i = 1, #seq do
    local e = entries[start + i - 1]
    if e.key ~= seq[i] then return false end
    if e.mode ~= "n" and e.mode ~= "no" then return false end
    if i > 1 then
      local prev = entries[start + i - 2]
      if (e.time - prev.time) > max_gap_ms then return false end
    end
  end
  return true
end

--- Create a "spam key" rule definition.
--- @param key string The key to detect spamming for
--- @param default_threshold number How many consecutive presses to trigger
--- @param suggestion string What to suggest instead
--- @return table rule
function M.spam_rule(key, default_threshold, suggestion)
  return {
    id = "spam_" .. key,
    name = "Spamming " .. key,
    description = ("Detects %d+ consecutive '%s' presses"):format(default_threshold, key),
    severity = "warning",
    suggestion = suggestion,
    default_threshold = default_threshold,
    detect = function(entries, config)
      local threshold = (config and config.threshold) or default_threshold
      local count = M.count_consecutive_tail(entries, key)
      if count >= threshold then
        return { count = count }
      end
      return nil
    end,
  }
end

--- Check if an entry is in normal mode.
--- @param entry table
--- @return boolean
function M.is_normal(entry)
  return entry.mode == "n" or entry.mode == "no"
end

return M
