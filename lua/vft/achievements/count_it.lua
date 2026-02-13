return {
  id = "count_it",
  name = "Count It",
  icon = "\u{1f522}",
  description = "Use a count prefix 10 times in one session",
  check = function(store)
    return store.get_counter("count_prefix_used") >= 10
  end,
}
