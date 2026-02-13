return {
  id = "hjkl_over_search",
  name = "hjkl instead of search",
  description = "Excessive h/j/k/l travel when / or f would be faster",
  severity = "coach",
  suggestion = "Use /word or f{char} for long-distance jumps instead of holding hjkl",
  detect = function(entries, _config)
    if #entries < 10 then return nil end

    local hjkl_keys = { h = true, j = true, k = true, l = true }
    local jump_keys = {
      ["/"] = true, ["?"] = true, ["f"] = true, ["F"] = true,
      ["t"] = true, ["T"] = true, ["{"] = true, ["}"] = true,
      ["G"] = true, ["n"] = true, ["N"] = true,
    }

    local hjkl_count = 0
    local first_time = nil
    local last_time = nil

    for _, e in ipairs(entries) do
      if e.mode ~= "n" and e.mode ~= "no" then goto next end

      if jump_keys[e.key] then
        return nil
      end

      if hjkl_keys[e.key] then
        hjkl_count = hjkl_count + 1
        if not first_time then first_time = e.time end
        last_time = e.time
      end

      ::next::
    end

    if hjkl_count >= 10 and first_time and last_time then
      if (last_time - first_time) <= 4000 then
        return { count = hjkl_count }
      end
    end
    return nil
  end,
}
