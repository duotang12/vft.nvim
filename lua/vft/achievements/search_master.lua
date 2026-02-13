return {
  id = "search_master",
  name = "Search Master",
  icon = "\u{1f50d}",
  description = "Use / or ? 50 times total",
  check = function(store)
    local slash = store.get_lifetime_motion("/")
    local question = store.get_lifetime_motion("?")
    return (slash + question) >= 50
  end,
}
