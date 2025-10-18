<p align="center">
        <h2 align="center">atone.nvim</h2>
</p>

<p align="center">
        Modern undotree plugin for nvim
</p>

<p align="center">
        <a href="https://github.com/XXiaoA/atone.nvim/stargazers">
                <img alt="Stars" src="https://img.shields.io/github/stars/XXiaoA/atone.nvim?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41"></a>
        <a href="https://github.com/XXiaoA/atone.nvim/issues">
                <img alt="Issues" src="https://img.shields.io/github/issues/XXiaoA/atone.nvim?style=for-the-badge&logo=bilibili&color=F5E0DC&logoColor=D9E0EE&labelColor=302D41"></a>
        <a href="https://github.com/XXiaoA/atone.nvim">
                <img alt="License" src="https://img.shields.io/github/license/XXiaoA/atone.nvim?color=%23DDB6F2&label=LICENSE&logo=codesandbox&style=for-the-badge&logoColor=D9E0EE&labelColor=302D41"/></a>
</p>

<img width="2536" height="1518" alt="Image" src="https://github.com/user-attachments/assets/2ed40e9a-c3da-49c6-888c-697aa4b391c8" />

## Features

* **Blazing Fast**
* **Mordern UI**
* **Live Diff:** Instantly see the difference between the selected undo-history state and its parent.
* **Auto-attaching Tree:** The undo tree automatically follows you as you switch between buffers.
* **Highly Customizable:** Almost every aspect can be configured.

## Installation

You can install `atone.nvim` using your favorite plugin manager. Here comes a example for *lazy.nvim*

```lua
{
    "XXiaoA/atone.nvim",
    cmd = "Atone",
    opts = {}, -- your configuration here
}
```

## Commands

The main command is `:Atone`. It has the following subcommands:

| Command                   | Description                               |
| ------------------------- | ----------------------------------------  |
| `:Atone` or `:Atone open` | Opens the undo tree view.                 |
| `:Atone toggle`           | Toggles the undo tree view on and off.    |
| `:Atone close`            | Closes the undo tree view.                |
| `:Atone focus`            | Moves the cursor to the undo tree window. |

## Configuration

You can configure `atone.nvim` by passing a table to the `setup` function. Here are the default options:

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
    keymaps = {
        tree = {
            quit = { "<C-c>", "q" },
            next_node = "j", -- support v:count
            pre_node = "k", -- support v:count
            undo_to = "<CR>",
            help = { "?", "g?" },
        },
        auto_diff = {
            quit = { "<C-c>", "q" },
            help = { "?", "g?" },
        },
        help = {
            quit_help = { "<C-c>", "q" },
        },
    },
    ui = {
        -- refer to `:h 'winborder'`
        border = "single",
    },
})
```

### Keymap Actions

The `keymaps` table in the configuration allows you to map keys to specific actions in different windows. The keys can be a single string or a table of strings.

Here are the available actions and their default keybindings:

| Action      | Default Key(s) | Description                                                     |
| ---         | ---            | ---                                                             |
| `next_node` | `j`            | Jump to the next node in the undo tree. Supports `v:count`.     |
| `pre_node`  | `k`            | Jump to the previous node in the undo tree. Supports `v:count`. |
| `undo_to`   | `<CR>`         | Revert the buffer to the state of the node under the cursor.    |
| `quit`      | `<C-c>`, `q`   | Close all `atone.nvim` windows (tree, diff, and help).          |
| `help`      | `?`, `g?`      | Show the help page.                                             |
| `quit_help` | `<C-c>`, `q`   | Close the help window.                                          |

## Highlighting

`atone.nvim` uses the following highlight groups. You can customize them as what you did for normal highlight groups.

| Highlight Group    | Default           | Description                                       |
| ---                | ---               | ---                                               |
| `AtoneSeq`         | link to `Number`  | The sequence number of each node                  |
| `AtoneSeqBracket`  | link to `Comment` | The brackets surrounding the node sequence number |
| `AtoneCurrentNode` | link to `Keyword` | The currently selected node in the undo tree      |

## Credits

- Heavily inspired by [vim-mundo](https://github.com/simnalamburt/vim-mundo)
- Refer to user commands implementation in [nvim-best-practices](https://github.com/nvim-neorocks/nvim-best-practices)
