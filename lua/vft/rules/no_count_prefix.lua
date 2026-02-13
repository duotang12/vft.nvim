return {
  id = "no_count_prefix",
  name = "No count prefix usage",
  description = "Repeated single motions without using count prefixes",
  severity = "coach",
  suggestion = "Try using count prefixes like 5j instead of pressing j repeatedly",
  detect = function(entries, _config)
    if #entries < 15 then return nil end

    local dominated_key = nil
    local hjkl = { h = 0, j = 0, k = 0, l = 0 }
    local digits_seen = false
    local normal_count = 0

    for _, e in ipairs(entries) do
      if e.mode == "n" or e.mode == "no" then
        normal_count = normal_count + 1
        if hjkl[e.key] then
          hjkl[e.key] = hjkl[e.key] + 1
        end
        local byte = string.byte(e.key, 1)
        if byte and byte >= 49 and byte <= 57 then
          digits_seen = true
        end
      end
    end

    if digits_seen then return nil end
    if normal_count < 15 then return nil end

    for key, count in pairs(hjkl) do
      if count >= math.floor(normal_count * 0.6) then
        dominated_key = key
        break
      end
    end

    if dominated_key then
      return { key = dominated_key }
    end
    return nil
  end,
}
