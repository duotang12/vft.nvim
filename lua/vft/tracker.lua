local store = require("vft.store")
local utils = require("vft.utils")

local M = {}

--- Ring buffer for recent keystrokes.
--- Each entry: { key = string, time = number (ms), mode = string }
local buffer = {}
local buffer_size = 100
local buffer_pos = 0
local buffer_count = 0

local on_key_ns = nil
local enabled = false
local analyze_timer = nil
local analyze_fn = nil -- set by init to avoid circular require
local pending_analyze = false -- flag to schedule immediate analysis

-- Track consecutive same-key presses for instant spam detection
local last_normal_key = nil
local consecutive_count = 0
local SPAM_QUICK_THRESHOLD = 3 -- trigger immediate analysis after this many repeats

-- Keys we track as "motions" in normal mode
local MOTION_KEYS = {
  ["j"] = true, ["k"] = true, ["h"] = true, ["l"] = true,
  ["w"] = true, ["W"] = true, ["b"] = true, ["B"] = true,
  ["e"] = true, ["E"] = true, ["0"] = true, ["$"] = true,
  ["^"] = true, ["{"] = true, ["}"] = true, ["G"] = true,
  ["f"] = true, ["F"] = true, ["t"] = true, ["T"] = true,
  ["/"] = true, ["?"] = true, ["n"] = true, ["N"] = true,
  ["x"] = true, ["d"] = true, ["y"] = true, ["c"] = true,
  ["p"] = true, ["P"] = true, ["v"] = true, ["V"] = true,
  ["i"] = true, ["I"] = true, ["a"] = true, ["A"] = true,
  ["o"] = true, ["O"] = true, ["s"] = true, ["S"] = true,
}

--- Translate raw key bytes into a readable name.
--- @param raw string The raw key from vim.on_key
--- @return string|nil Readable key name, or nil to ignore
local function translate_key(raw)
  if not raw or raw == "" then return nil end

  -- Try to decode termcodes
  local byte = string.byte(raw, 1)

  -- Escape
  if byte == 27 then return "<Esc>" end
  -- Carriage return
  if byte == 13 then return "<CR>" end
  -- Backspace
  if byte == 8 or byte == 127 then return "<BS>" end
  -- Tab
  if byte == 9 then return "<Tab>" end

  -- Control characters (1-26 map to Ctrl-A through Ctrl-Z)
  if byte >= 1 and byte <= 26 then
    return "<C-" .. string.char(byte + 96) .. ">"
  end

  -- Printable ASCII
  if byte >= 32 and byte <= 126 then
    return raw
  end

  -- Multi-byte / special keys - try vim.fn.keytrans
  local ok, translated = pcall(vim.fn.keytrans, raw)
  if ok and translated ~= "" then
    return translated
  end

  return nil
end

--- Push a keystroke into the ring buffer.
--- @param key string
--- @param mode string
local function push(key, mode)
  buffer_pos = (buffer_pos % buffer_size) + 1
  buffer[buffer_pos] = {
    key = key,
    time = utils.now_ms(),
    mode = mode,
  }
  if buffer_count < buffer_size then
    buffer_count = buffer_count + 1
  end
end

--- Get the last N entries from the ring buffer (oldest first).
--- @param n number|nil How many entries (defaults to all)
--- @return table[]
function M.get_recent(n)
  n = math.min(n or buffer_count, buffer_count)
  if n == 0 then return {} end
  local result = {}
  local start = ((buffer_pos - n) % buffer_size) + 1
  for i = 0, n - 1 do
    local idx = ((start - 1 + i) % buffer_size) + 1
    result[#result + 1] = buffer[idx]
  end
  return result
end

--- Get only the key strings from the last N entries.
--- @param n number|nil
--- @return string[]
function M.get_recent_keys(n)
  local entries = M.get_recent(n)
  local keys = {}
  for _, e in ipairs(entries) do
    keys[#keys + 1] = e.key
  end
  return keys
end

--- Set the analysis callback (called on a debounced timer).
--- @param fn function(buffer_entries: table[])
function M.set_analyzer(fn)
  analyze_fn = fn
end

--- Start tracking keystrokes.
function M.start()
  if enabled then return end
  enabled = true

  on_key_ns = vim.on_key(function(raw, typed)
    if not enabled then return end
    -- Use typed if available (Neovim 0.10+), otherwise raw
    local src = typed or raw
    local key = translate_key(src)
    if not key then return end

    local mode = vim.api.nvim_get_mode().mode

    -- Record keystroke in store
    store.record_keystroke()

    -- Record motion if applicable (only in normal/visual modes)
    if (mode == "n" or mode == "v" or mode == "V" or mode == "\22") then
      if MOTION_KEYS[key] then
        store.record_motion(key)
      end
    end

    -- Track count prefixes (digits 1-9 in normal mode before a motion)
    if mode == "n" or mode == "no" then
      local byte = string.byte(key, 1)
      if byte and byte >= 49 and byte <= 57 then
        store.increment_counter("count_prefix_used")
      end
    end

    -- Track text object usage (i/a in operator-pending mode = text objects)
    if mode == "no" and (key == "i" or key == "a") then
      store.increment_counter("text_object_used")
    end

    -- Push to ring buffer
    push(key, mode)

    -- Track consecutive same-key for instant spam detection
    if mode == "n" or mode == "no" then
      if key == last_normal_key then
        consecutive_count = consecutive_count + 1
      else
        last_normal_key = key
        consecutive_count = 1
      end

      -- Schedule immediate analysis when spam threshold is hit
      if consecutive_count >= SPAM_QUICK_THRESHOLD and analyze_fn and not pending_analyze then
        pending_analyze = true
        vim.schedule(function()
          pending_analyze = false
          if not enabled or not analyze_fn then return end
          local entries = M.get_recent(20)
          analyze_fn(entries)
        end)
      end
    else
      last_normal_key = nil
      consecutive_count = 0
    end
  end)

  -- Background timer for complex (non-spam) rules - runs every 2s
  analyze_timer = vim.loop.new_timer()
  analyze_timer:start(2000, 2000, vim.schedule_wrap(function()
    if not enabled then return end
    if analyze_fn and buffer_count > 0 then
      local entries = M.get_recent(20)
      analyze_fn(entries)
    end
  end))
end

--- Stop tracking keystrokes.
function M.stop()
  if not enabled then return end
  enabled = false

  if on_key_ns then
    pcall(vim.on_key, nil, on_key_ns)
    on_key_ns = nil
  end

  if analyze_timer then
    analyze_timer:stop()
    analyze_timer:close()
    analyze_timer = nil
  end
end

--- Check if tracking is active.
function M.is_running()
  return enabled
end

--- Clear the ring buffer.
function M.clear()
  buffer = {}
  buffer_pos = 0
  buffer_count = 0
end

return M
