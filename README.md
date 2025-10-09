# Atone.nvim

_atone.nvim_ is a modern undotree plugin for Neovim.

<!-- vim-markdown-toc GFM -->

- [Install](#install)
- [Command](#command)
- [Configuration](#configuration)
- [Highlight](#highlight)
- [Credits](#credits)

<!-- vim-markdown-toc -->

## Install

- using [lazy.nvim]https://github.com/folke/lazy.nvim()

```
{
  "XXiaoA/atone.nvim",
  cmd = "Atone"
}

```

- using [nvim-plug](https://github.com/wsdjeg/nvim-plug)

```lua
require("plug").add({
    "XXiaoA/atone.nvim",
    cmds = { "Atone" },
})
```

## Command

main command: `Atone`

subcommand: `toggle`, `open`, `close`, `focus`

## Configuration

```lua
require("atone").setup({
    layout = {
        ---@type "left"|"right"
        direction = "left",
        ---@type "adaptive"|integer|number
        --- adaptive: exact the width of tree graph
        --- if number given is a float less than 1, the width is set to `vim.o.columns * that number`
        width = 0.25,
    },
    -- diff for the node under cursor
    -- shown under the tree graph
    diff_cur_node = {
        enabled = true,
        ---@type number float less than 1
        --- The diff window's height is set to a specified percentage of the original (namely tree graph) window's height.
        split_percent = 0.3,
    },
    -- automatically update the buffer that the tree is attached to
    -- only works for buffer whose buftype is <empty>
    auto_attach = {
        enabled = true,
        excluded_ft = { "oil" },
    },
})
```

## Highlight

- `ID`: { link = "Number" }
- `CurrentNode`: { link = "Keyword" }
- `IDBracket`: { link = "Comment" }

## Credits

- Heavily inspired by [vim-mundo](https://github.com/simnalamburt/vim-mundo)
- Reference user commands implementation from [nvim-best-practices](https://github.com/nvim-neorocks/nvim-best-practices)
