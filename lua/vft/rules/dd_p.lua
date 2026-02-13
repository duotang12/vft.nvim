local h = require("vft.rules.helpers")

return {
  id = "dd_p",
  name = "dd then p to move line",
  description = "Detects dd followed quickly by p (line swap pattern)",
  severity = "hint",
  suggestion = "Use :m+1/:m-1 or ddp shortcut to move lines",
  detect = function(entries, _config)
    if h.tail_matches_seq(entries, { "d", "d", "p" }, 2000) then
      return {}
    end
    return nil
  end,
}
