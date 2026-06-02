# typst-outline.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A sidebar outline for [Typst](https://typst.app/) documents in Neovim.

Follows `#include` directives recursively across multiple files to build a full document outline with hierarchical numbering and Catppuccin Mocha colors.

[中文文档](https://github.com/gitefdf/typst-outline.nvim/blob/main/README_zh.md)

---

## ✨ Features

- Recursively resolves `#include` and `#import` to build a complete multi-file outline
- Auto-discovers the root file from any sub-file — zero configuration needed
- Hierarchical numbering: `1`, `1.1`, `1.1.1`
- Catppuccin Mocha palette per heading level (fully customizable)
- File separator lines for every included file, even those without headings
- Toggleable depth filter (`1`~`9` to limit visible levels)
- Cursor tracking — the outline follows you through the document
- Auto-refresh on save with mtime-based caching
- Persistent cache across Neovim sessions (`~/.cache/typst-outline/`)
- Root file hint via `// typst-root: true` comment or `b:typst_main` variable

## 📦 Installation

### lazy.nvim

```lua
{
  "gitefdf/typst-outline.nvim",
  opts = {},
  keys = {
    { "<leader>to", "<cmd>TypstOutline<CR>", desc = "Typst Outline" },
  },
}
```

### packer.nvim

```lua
use {
  "gitefdf/typst-outline.nvim",
  config = function()
    require("typst-outline").setup({})
  end,
}
```

### Nvim 0.12 built-in

```lua
vim.plugin.add("gitefdf/typst-outline.nvim", {
  config = function()
    require("typst-outline").setup({})
  end,
})
```

## 🚀 Usage

### Commands

| Command | Description |
| --- | --- |
| `:TypstOutline` | Toggle the outline sidebar |
| `:TypstOutlineRefresh` | Force a full re-parse |
| `:TypstOutlineClose` | Close the sidebar |
| `:TypstCompile` | Start typst watch + open Zathura |
| `:TypstCompileStop` | Stop typst watch and Zathura (auto on exit) |
| `:TypstCompileErrors` | Show last compile errors in a split buffer |

### Keymaps

> Only active inside the outline window.

| Key | Description |
| --- | --- |
| `<CR>` / `o` / double-click | Jump to heading or file |
| `q` / `<Esc>` | Close the outline |
| `r` | Refresh |
| `0` | Show all levels |
| `1` ~ `9` | Show up to level N |
| `]]` / `[[` | Jump to next/previous level-1 heading |

## ⚙️ Configuration

```lua
require("typst-outline").setup({
  auto_refresh = true,       -- auto-refresh on save
  focus_on_open = true,      -- jump to current heading when opened
  split_direction = "left",  -- "left" | "right" | "above" | "below"
  split_width = 35,          -- sidebar width in columns
  max_depth = 10,            -- max #include recursion depth
  max_level = nil,           -- initial level cap (nil = show all)
  sync_cursor = true,        -- track document cursor in outline
  sync_debounce = 50,        -- cursor sync debounce in ms
  highlights = {             -- override heading colors
    H1 = { fg = "#cba6f7", bold = true },
    H2 = { fg = "#94e2d5" },
    -- ... up to H9
    File = { fg = "#9399b2", bold = true },
  },
})
```

> Everything is optional — the defaults above are what you get with `setup({})`.

## 🔍 How It Works

**Root file discovery.** Starting from whatever sub-file you're editing, the plugin walks up the directory tree scanning every `.typ` file for a `#include` that references your current file. Found a parent? It keeps climbing — checking if that parent is also included by a higher file — until it reaches the true root. You can also mark any file's first 5 lines with `// typst-root: true` to stop the search there. Or set `vim.b.typst_main` to a path (e.g. `:lua vim.b.typst_main = "/path/to/main.typ"`) to bypass discovery entirely and use a specific file. No filename conventions, no manual setup.

**Outline parsing.** Parses the root file line by line. Both `= Heading` and `#heading(level: N)[text]` syntaxes are supported. `#include "file.typ"` and `#import "file.typ"` trigger a recursive descent into the included file, inserting its headings inline in document order. `@package` imports are automatically skipped. Comments are ignored, circular includes are caught, and includes missing the `.typ` extension are auto-resolved. Files with no headings still appear as jumpable entries.

**Display.** Headings are filtered by the current depth setting, then rendered with hierarchical numbering and Catppuccin Mocha colors. Empty headings show only their number. The main file always appears first as a jumpable entry.

**Caching.** Parsed files are cached by modification time. Switching levels or refreshing only re-reads files that actually changed. Cache is persisted to `~/.cache/typst-outline/cache.json` across sessions, so restarting Neovim doesn't require a full re-parse.

## 🎨 Highlight Groups

| Group | Color | Level |
| --- | --- | --- |
| `TypstOutlineH1` | Mauve bold `#cba6f7` | Level 1 |
| `TypstOutlineH2` | Teal `#94e2d5` | Level 2 |
| `TypstOutlineH3` | Yellow `#f9e2af` | Level 3 |
| `TypstOutlineH4` | Peach `#fab387` | Level 4 |
| `TypstOutlineH5` | Pink `#f5c2e7` | Level 5 |
| `TypstOutlineH6` | Lavender `#b4befe` | Level 6 |
| `TypstOutlineH7` | Sky `#89dceb` | Level 7 |
| `TypstOutlineH8` | Green `#a6e3a1` | Level 8 |
| `TypstOutlineH9` | Flamingo `#f2cdcd` | Level 9 |
| `TypstOutlineFile` | Overlay2 bold `#9399b2` | File separator |

> Set the `highlights` option to override any of these.

## 📄 License

MIT

---

## Begging for Stars

If you find this plugin useful, please give me a star (spiritual encouragement — please, please, please give me a star).

No need to sponsor (but if you insist — I really do want the money, and I'm very short on it, I just don't know how to accept payments).

My programming skills are very poor. If you think this plugin could be improved and want to contribute, don't push code — I don't know how to pull. You can fork the repo. Of course, if you'd be willing to link to my repo in your own plugin's README and ask for a star on my behalf, that'd be even better.

If you have feature requests or think something needs improving, you're welcome to open an issue (but honestly, it probably won't help — I may not have the ability to fix it).
