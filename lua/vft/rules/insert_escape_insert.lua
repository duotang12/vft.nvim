return {
  id = "insert_escape_insert",
  name = "Quick insert-escape-insert",
  description = "Entering insert mode, exiting, then re-entering within 2 seconds",
  severity = "coach",
  suggestion = "Stay in insert mode, or use A/I/o/O to reposition",
  detect = function(entries, _config)
    if #entries < 3 then return nil end
    local insert_keys = { i = true, I = true, a = true, A = true, o = true, O = true }
    local last = entries[#entries]
    if not insert_keys[last.key] then return nil end
    if last.mode ~= "n" then return nil end

    for i = #entries - 1, math.max(1, #entries - 5), -1 do
      local e = entries[i]
      if e.key == "<Esc>" then
        if (last.time - e.time) <= 2000 then
          for j = i - 1, math.max(1, i - 3), -1 do
            if insert_keys[entries[j].key] then
              return {}
            end
          end
        end
        break
      end
    end
    return nil
  end,
}
