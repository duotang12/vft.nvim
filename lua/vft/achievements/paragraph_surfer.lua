return {
  id = "paragraph_surfer",
  name = "Paragraph Surfer",
  icon = "\u{1f3c4}",
  description = "Use { and } 50 times total",
  check = function(store)
    local open = store.get_lifetime_motion("{")
    local close = store.get_lifetime_motion("}")
    return (open + close) >= 50
  end,
}
