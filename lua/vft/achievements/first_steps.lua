return {
  id = "first_steps",
  name = "First Steps",
  icon = "\u{1f476}",
  description = "Use a text object for the first time",
  check = function(store)
    return store.get_counter("text_object_used") >= 1
  end,
}
