return {
  id = "streak_7",
  name = "Streak!",
  icon = "\u{1f525}",
  description = "7 consecutive days of Neovim usage",
  check = function(store)
    local data = store.get_data()
    return data.streak_current >= 7
  end,
}
