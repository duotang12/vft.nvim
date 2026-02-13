# vft.nvim

**A fitness tracker for your Vim motions.**

I built this as a small tool to help myself get better at Vim. I kept catching myself spamming `jjjjjj` instead of using `5j`, or mashing `llllll` when `f` would get me there in one keystroke. So I made something that would watch how I move and nudge me toward better habits.

It's been running in my own setup for a while now and it's actually helped, so I'm putting it out there in case it helps someone else too. It's not meant to be annoying - just a quiet coach that speaks up when you're doing something the hard way.

> Stop mashing `jjjjjj`. Start moving like a Vim athlete.

## Preview

<video src="assets/demo.mp4" autoplay loop muted playsinline></video>

## Features

- **Passive keystroke tracking** - uses `vim.on_key()` to monitor all motions without interfering with your workflow
- **Anti-pattern detection** - catches bad habits like key spamming (`jjjjj` instead of `5j`), unnecessary mode switches, and more
- **Real-time coaching** - non-intrusive floating window suggestions that auto-dismiss
- **Dashboard** - `:VFT` opens a stats dashboard with motion charts, efficiency scores, and trends
- **Gamification** - earn XP for efficient motions, level up, unlock achievements, and maintain usage streaks
- **JSON persistence** - all data saved to disk automatically

## Installation

### lazy.nvim

```lua
{
  "duotang12/vft.nvim",
  event = "VeryLazy",
  opts = {},
}
```

### packer.nvim

```lua
use {
  "duotang12/vft.nvim",
  config = function()
    require("vft").setup()
  end,
}
```

### vim-plug

```vim
Plug 'duotang12/vft.nvim'

" In your init.lua or after/plugin:
lua require("vft").setup()
```

## Configuration

All options with their defaults:

```lua
require("vft").setup({
  enabled = true,
  notify = {
    enabled = true,
    position = "top_right",  -- "top_right", "bottom_right", "cursor"
    timeout = 3000,          -- ms before auto-dismiss
    cooldown = 30,           -- seconds before same rule fires again
  },
  rules = {
    -- Override any rule's config:
    -- spam_j = { enabled = true, threshold = 4 },
    -- spam_k = { enabled = true, threshold = 4 },
    -- spam_h = { enabled = true, threshold = 6 },
    -- spam_l = { enabled = true, threshold = 6 },
    -- spam_w = { enabled = true, threshold = 5 },
    -- spam_x = { enabled = true, threshold = 3 },
  },
  gamification = {
    enabled = true,
    xp_per_efficient_motion = 1,
    xp_penalty_per_antipattern = 5,
  },
  dashboard = {
    width = 60,
    height = 30,
  },
  custom_rules_dir = nil,        -- path to custom rule .lua files
  custom_achievements_dir = nil,  -- path to custom achievement .lua files
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:VFT` | Open the stats dashboard |
| `:VFTStats` | Print today's summary to the command line |
| `:VFTReset` | Reset all data (requires confirmation) |
| `:VFTEnable` | Enable keystroke tracking |
| `:VFTDisable` | Disable keystroke tracking |
| `:VFTRules` | List all rules with their enabled/disabled status |
| `:VFTRules enable <id>` | Enable a rule |
| `:VFTRules disable <id>` | Disable a rule |
| `:VFTRules toggle <id>` | Toggle a rule on/off |
| `:VFTAchievements` | Show all achievements and progress |

## Anti-Pattern Rules

| Rule | Detects | Suggests |
|------|---------|----------|
| `spam_j` | 4+ consecutive `j` | Use `{n}j` or `}` |
| `spam_k` | 4+ consecutive `k` | Use `{n}k` or `{` |
| `spam_h` | 6+ consecutive `h` | Use `b`, `B`, `F{char}`, `0`/`^` |
| `spam_l` | 6+ consecutive `l` | Use `w`, `e`, `f{char}`, `$` |
| `spam_w` | 5+ consecutive `w` | Use `f{char}` or `/pattern` |
| `spam_x` | 3+ consecutive `x` | Use `d{n}l` or `dt{char}` |
| `dd_p` | `dd` then `p` quickly | Use `:m+1`/`:m-1` |
| `visual_yank_small` | `v` + small motion + `y` | Use `yw` or `yiw` directly |
| `no_count_prefix` | Repeated single motions without counts | Use `5j` instead of `jjjjj` |
| `hjkl_over_search` | 10+ hjkl in rapid succession | Use `/word` or `f{char}` for long jumps |
| `insert_escape_insert` | Quick insert-escape-insert | Stay in insert mode or use `A`/`I`/`o`/`O` |

## Achievements

| Badge | Name | How to earn |
|-------|------|-------------|
| :baby: | First Steps | Use a text object for the first time |
| :1234: | Count It | Use a count prefix 10 times in one session |
| :mag: | Search Master | Use `/` or `?` 50 times total |
| :fire: | Streak! | 7 consecutive days of Neovim usage |
| :sparkles: | Clean Day | A full session with 0 anti-pattern warnings |
| :surfer: | Paragraph Surfer | Use `{` and `}` 50 times total |

## How It Works

1. `vim.on_key()` intercepts every keystroke and pushes it into a ring buffer
2. A debounced timer (every 500ms) runs the analyzer against the recent buffer
3. Each rule's `detect()` function scans for its pattern
4. When a match is found, a floating notification appears and the event is logged
5. Stats are persisted to `~/.local/share/nvim/vft.json` on exit and every 5 minutes

The hot path (keystroke capture) is kept minimal - heavy analysis runs on the timer.

## Custom Rules

You can add your own rules in two ways:

### 1. Drop a file in a custom rules directory

Set `custom_rules_dir` in your config:

```lua
require("vft").setup({
  custom_rules_dir = "~/.config/nvim/vft-rules",
})
```

Then create a `.lua` file in that directory. Each file should return a rule table:

```lua
-- ~/.config/nvim/vft-rules/spam_b.lua
return {
  id = "spam_b",
  name = "Spamming b",
  description = "Detects 5+ consecutive b presses",
  severity = "warning",
  suggestion = "Use F{char} or ? to jump back faster",
  detect = function(entries, config)
    local count = 0
    for i = #entries, 1, -1 do
      if entries[i].key == "b" and entries[i].mode == "n" then
        count = count + 1
      else
        break
      end
    end
    if count >= (config and config.threshold or 5) then
      return { count = count }
    end
    return nil
  end,
}
```

**Using the helpers module:**

The built-in helpers make common patterns trivial. For example, a spam rule is a one-liner:

```lua
-- ~/.config/nvim/vft-rules/spam_b.lua
local h = require("vft.rules.helpers")
return h.spam_rule("b", 5, "Use F{char} or ? to jump back faster")
```

**Available helpers:**

| Function | Description |
|----------|-------------|
| `helpers.spam_rule(key, threshold, suggestion)` | Creates a complete spam detection rule |
| `helpers.count_consecutive_tail(entries, key)` | Count consecutive presses of `key` at the end of the buffer |
| `helpers.tail_matches_seq(entries, seq, max_gap_ms)` | Check if a key sequence (e.g. `{"d","d","p"}`) appears at the tail |
| `helpers.is_normal(entry)` | Check if an entry is in normal mode |

**Rule anatomy:**

Your `detect(entries, config)` function receives:
- `entries` - a list of recent keystrokes, oldest first. Each entry has:
  - `.key` - the key name (`"j"`, `"w"`, `"<Esc>"`, `"<C-d>"`, etc.)
  - `.time` - timestamp in milliseconds
  - `.mode` - Neovim mode (`"n"`, `"i"`, `"v"`, `"no"`, etc.)
- `config` - the per-rule config from the user's `setup()` (e.g. `{ threshold = 6 }`)

Return a table (any truthy value) to trigger the rule, or `nil` to skip.

The `severity` field controls the notification style:
- `"hint"` - subtle, informational
- `"warning"` - more visible
- `"coach"` - general coaching advice

### 2. Toggle rules at runtime

```vim
:VFTRules                    " list all rules
:VFTRules disable spam_j     " disable a rule
:VFTRules enable spam_j      " re-enable it
:VFTRules toggle spam_j      " toggle on/off
```

Or disable rules in your config:

```lua
require("vft").setup({
  rules = {
    spam_j = { enabled = false },
  },
})
```

## Custom Achievements

Achievements work just like rules - drop a `.lua` file in a directory and it's auto-discovered.

Set `custom_achievements_dir` in your config:

```lua
require("vft").setup({
  custom_achievements_dir = "~/.config/nvim/vft-achievements",
})
```

Each file returns an achievement table with a `check(store)` function:

```lua
-- ~/.config/nvim/vft-achievements/speed_demon.lua
return {
  id = "speed_demon",
  name = "Speed Demon",
  icon = "\u{26a1}",
  description = "Reach 10,000 total keystrokes",
  check = function(store)
    local data = store.get_data()
    local total = 0
    for _, day in pairs(data.daily_stats) do
      total = total + (day.keystrokes or 0)
    end
    return total >= 10000
  end,
}
```

**Available store functions for `check(store)`:**

| Function | Returns |
|----------|---------|
| `store.get_data()` | Full data table (daily_stats, total_xp, level, streak, etc.) |
| `store.today()` | Today's stats (keystrokes, motions, antipatterns, etc.) |
| `store.get_counter(name)` | Lifetime counter value (e.g. `"text_object_used"`, `"count_prefix_used"`) |
| `store.get_lifetime_motion(key)` | All-time count for a specific motion key |
| `store.has_achievement(id)` | Whether an achievement is already earned |

Achievements are checked every 60 seconds and on session exit.

## Contributing

Contributions are welcome! Here's how to add a new built-in rule or achievement:

**Rules:**

1. Create a new `.lua` file in `lua/vft/rules/`
2. Return a table with: `id`, `name`, `description`, `severity`, `suggestion`, and `detect(entries, config)`
3. `detect()` receives the recent keystroke buffer and returns a match table or `nil`
4. Auto-discovered - no registration needed

**Achievements:**

1. Create a new `.lua` file in `lua/vft/achievements/`
2. Return a table with: `id`, `name`, `icon`, `description`, and `check(store)`
3. `check(store)` returns `true` when the achievement should be granted
4. Auto-discovered - no registration needed

## License

MIT
