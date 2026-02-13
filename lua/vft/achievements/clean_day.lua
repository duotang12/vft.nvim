return {
  id = "clean_day",
  name = "Clean Day",
  icon = "\u{2728}",
  description = "A full session with 0 anti-pattern warnings",
  check = function(store)
    local day = store.today()
    -- Only counts if you actually did some work
    if day.keystrokes < 100 then return false end
    local ap_count = 0
    for _, c in pairs(day.antipatterns) do
      ap_count = ap_count + c
    end
    return ap_count == 0
  end,
}
