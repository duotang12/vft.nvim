return {
  id = "visual_yank_small",
  name = "Visual mode for small yank",
  description = "Entering visual mode + small motion + y when yw/yiw would suffice",
  severity = "hint",
  suggestion = "Use yw, yiw, or yi\" instead of visual selecting then yanking",
  detect = function(entries, _config)
    if #entries < 3 then return nil end
    local last = entries[#entries]
    if last.key ~= "y" then return nil end

    local motion_count = 0
    local small_motions = {
      w = true, W = true, e = true, E = true, b = true, B = true,
      l = true, h = true, ["$"] = true, ["^"] = true, ["0"] = true,
    }
    for i = #entries - 1, math.max(1, #entries - 5), -1 do
      local e = entries[i]
      if e.key == "v" and (e.mode == "n" or e.mode == "no") then
        if motion_count >= 1 and motion_count <= 3 then
          if (last.time - e.time) <= 3000 then
            return { motion_count = motion_count }
          end
        end
        return nil
      elseif small_motions[e.key] then
        motion_count = motion_count + 1
      else
        return nil
      end
    end
    return nil
  end,
}
