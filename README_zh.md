# typst-outline.nvim

Typst 文档大纲侧栏，支持多文件项目。

递归追踪 `#include` 构建完整文档大纲，层级编号显示，Catppuccin Mocha 主题着色。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## ✨ 功能

- 递归追踪 `#include` 与 `#import`，跨文件构建完整大纲
- 在任意子文件中打开，自动发现根文件，无需指定
- 层级编号：`1` `1.1` `1.1.1`
- Catppuccin Mocha 主题配色（可自定义）
- 每个被引入的文件均显示分隔线，无标题文件也有入口
- 层级过滤（`1`~`9` 限定显示深度）
- 光标同步，文档移动时大纲自动跟随
- 保存时自动刷新，基于 mtime 缓存避免重复解析
- 跨会话持久化缓存（`~/.cache/typst-outline/`）
- 根文件标记 `// typst-root: true` 或 `b:typst_main` 变量

## 📦 安装

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

### Nvim 0.12 内置

```lua
vim.plugin.add("gitefdf/typst-outline.nvim", {
  config = function()
    require("typst-outline").setup({})
  end,
})
```

## 🚀 使用

### 命令

| 命令 | 说明 |
| --- | --- |
| `:TypstOutline` | 打开 / 关闭大纲侧栏 |
| `:TypstOutlineRefresh` | 强制重新解析刷新 |
| `:TypstOutlineClose` | 关闭侧栏 |
| `:TypstCompile` | 启动 typst watch 并打开 Zathura |
| `:TypstCompileStop` | 停止 typst watch 和 Zathura（退出 Neovim 自动调用） |
| `:TypstCompileErrors` | 在下方 split 窗口显示上次编译错误 |

### 侧栏快捷键

> 仅在大纲窗口内生效。

| 键 | 说明 |
| --- | --- |
| `<CR>` / `o` / 双击 | 跳转到标题或文件 |
| `q` / `<Esc>` | 关闭大纲 |
| `r` | 刷新 |
| `0` | 显示全部层级 |
| `1` ~ `9` | 仅显示 1~9 级标题 |
| `]]` / `[[` | 跳转到下一个/上一个一级标题 |

## ⚙️ 配置

```lua
require("typst-outline").setup({
  auto_refresh = true,       -- 保存 .typ 时自动刷新
  focus_on_open = true,      -- 打开大纲时定位到当前标题
  split_direction = "left",  -- 侧栏方向: "left" | "right" | "above" | "below"
  split_width = 35,          -- 侧栏宽度（列数）
  max_depth = 10,            -- #include 最大递归深度
  max_level = nil,           -- 初始显示层级，nil = 全部
  sync_cursor = true,        -- 若大纲打开，主文件内光标移动则大纲光标同步移动
  sync_debounce = 50,        -- 光标同步防抖延迟（毫秒）
  highlights = {             -- 自定义各级标题颜色
    H1 = { fg = "#cba6f7", bold = true },
    H2 = { fg = "#94e2d5" },
    -- ... 更多层级
    File = { fg = "#9399b2", bold = true },
  },
})
```

> 全部配置项均可选，默认值为示例中的值。

## 🔍 实现原理

**发现根文件：** 从当前文件所在目录逐级向上搜索，扫描每层目录中的 `.typ` 文件，检查是否通过 `#include` 引用了当前文件。找到后继续往上爬——检查该文件是否也被更上层的文件包含——直到真正的根。也可以在文件前 5 行写 `// typst-root: true` 直接标记为根，搜索到该文件即停。或通过 `vim.b.typst_main` 直接指定路径（如 `:lua vim.b.typst_main = "/path/to/main.typ"`），完全跳过自动发现。无需依赖特定文件名约定。

**解析大纲：** 从根文件出发逐行解析。支持 `= 标题` 和 `#heading(level: N)[标题]` 两种写法。`#include "file.typ"` 和 `#import "file.typ"` 会递归进入子文件，将其标题插入文档顺序中。`@package` 包引用自动排除。`//` 行注释和 `/* */` 块注释均被忽略，循环引用防护，无后缀 include 自动补全。无标题的文件也会显示入口。

**显示：** 按层级过滤后渲染，使用层级编号和 Catppuccin Mocha 颜色高亮。空标题仅显示编号。主文件始终显示在首行，可跳转。

**缓存：** 解析结果按文件修改时间缓存，层级切换或刷新时仅重读实际变动的文件。缓存持久化到 `~/.cache/typst-outline/cache.json`，重启 Neovim 无需重新解析全部文件。

## 🎨 高亮组

| 组名 | Mocha 色 | 层级 |
| --- | --- | --- |
| `TypstOutlineH1` | Mauve 粗体 `#cba6f7` | 一级 |
| `TypstOutlineH2` | Teal `#94e2d5` | 二级 |
| `TypstOutlineH3` | Yellow `#f9e2af` | 三级 |
| `TypstOutlineH4` | Peach `#fab387` | 四级 |
| `TypstOutlineH5` | Pink `#f5c2e7` | 五级 |
| `TypstOutlineH6` | Lavender `#b4befe` | 六级 |
| `TypstOutlineH7` | Sky `#89dceb` | 七级 |
| `TypstOutlineH8` | Green `#a6e3a1` | 八级 |
| `TypstOutlineH9` | Flamingo `#f2cdcd` | 九级 |
| `TypstOutlineFile` | Overlay2 粗体 `#9399b2` | 文件分隔 |

> 通过 `highlights` 配置项可覆盖任意高亮组。

## 📄 许可

MIT

---

## 乞丐恰 star

如您觉得这个插件不错，请您给予我一个 star（给我一个精神鼓励，求求你了给我一个star 呗）。

不用赞助（如果您想赞助的话），虽然我很想要钱，也很缺钱，但我不知道该怎么收钱。

如果您对这个插件有其他需求，或者认为这个插件有需要改进的地方，欢迎您提交 issue（不过大概率你提交了没啥用，我不一定有能力修改）。 13
