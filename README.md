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
* **Live Syntax-Aware Diff**: Instant, TreeSitter-powered diff previews with word-level inline highlighting.
* **Auto-attaching Tree:** The undo tree automatically follows you as you switch between buffers.
* **Node Marks:** Bookmark important undo states for quick navigation.
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
        --- adaptive: adapt to width of tree graph
        --- float < 1: width = vim.o.columns * value
        --- integer >= 1: absolute width
        width = 0.25,
    },
    -- diff for the node under cursor
    -- shown under the tree graph
    diff_cur_node = {
        enabled = true,
        ---@type number float less than 1
        --- The diff window's height is set to a specified percentage of the original (namely tree graph) window's height.
        split_percent = 0.3,
        ---@type "adaptive"|number
        --- adaptive: same width as tree window (default)
        --- float < 1: width = vim.o.columns * value
        --- integer >= 1: absolute width
        --- Note that non-adaptive values create a float diff window anchored to a hidden
        --- dummy split window. this is an implementation detail that may cause
        --- unexpected edge-case bugs in certain window layouts.
        width = "adaptive",
        -- Use TreeSitter to highlight the source code inside diff hunks.
        treesitter = true,
        -- Highlight the exact changed word ranges inside modified lines.
        inline_diff = true,
    },
    -- automatically update the buffer that the tree is attached to
    -- only works for buffer whose buftype is <empty>
    auto_attach = {
        enabled = true,
        excluded_ft = { "oil" },
    },
    marks = {
        persist = true,
        ---@type string
        persist_path = vim.fn.stdpath("data") .. "/atone_marks.json",
        ---@type string[]
        --- finders are tried in order. "builtin" is always available.
        finders = { "fzf-lua", "telescope", "builtin" },
    },
    keymaps = {
        tree = {
            quit = { "<C-c>", "q" },
            next_node = "j", -- support v:count
            pre_node = "k", -- support v:count
            jump_to_G = "G",
            jump_to_gg = "gg",
            undo_to = "<CR>",
            set_mark = "m",
            delete_mark = { "x", "X" },
            delete_all_marks = "dM",
            goto_mark = { "'", "`" },
            mark_picker = "s",
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
        -- compact graph style
        compact = false,
    },
})
```

### Keymap Actions

The `keymaps` table in the configuration allows you to map keys to specific actions in different windows. The keys can be a single string or a table of strings.

Here are the available actions and their default keybindings:

| Action        | Default Key(s) | Description                                                     |
| ---           | ---            | ---                                                             |
| `next_node`   | `j`            | Jump to the next node in the undo tree. Supports `v:count`.     |
| `pre_node`    | `k`            | Jump to the previous node in the undo tree. Supports `v:count`. |
| `jump_to_G`   | `G`            | Jump to the node with the specified sequence number like G      |
| `jump_to_gg`  | `gg`           | Jump to the node with the specified sequence number like gg     |
| `undo_to`     | `<CR>`         | Revert the buffer to the state of the node under the cursor.    |
| `set_mark`    | `m`            | Set a mark. Use `N:name` or `N` for slot (0-9).                 |
| `delete_mark` | `x`, `X`       | Delete the mark on the node under cursor.                       |
| `delete_all_marks` | `dM`      | Delete all marks in current buffer.                             |
| `goto_mark`   | `'`, `` ` ``   | Jump to a mark slot (0-9).                                      |
| `mark_picker` | `s`            | Open mark picker (fuzzy find).                                  |
| `quit`        | `<C-c>`, `q`   | Close all `atone.nvim` windows (tree, diff, and help).          |
| `help`        | `?`, `g?`      | Show the help page.                                             |
| `quit_help`   | `<C-c>`, `q`   | Close the help window.                                          |

## Highlighting

`atone.nvim` uses the following highlight groups. You can customize them as what you did for normal highlight groups.

| Highlight Group         | Default                   | Description                                       |
| ---                     | ---                       | ---                                               |
| `AtoneSeq`              | link to `Number`          | The sequence number of each node                  |
| `AtoneSeqBracket`       | link to `Comment`         | The brackets surrounding the node sequence number |
| `AtoneCurrentNode`      | link to `Keyword`         | The currently selected node in the undo tree      |
| `AtoneMark`             | link to `BookmarkSign`    | Mark labels on nodes                              |
| `AtoneDiffAdd`          | link to `DiffAdd`         | Background for added lines in the diff preview    |
| `AtoneDiffDelete`       | link to `DiffDelete`      | Background for removed lines in the diff preview  |
| `AtoneDiffAddInline`    | derived from `DiffAdd`    | Adaptive inline background for the changed range  |
| `AtoneDiffDeleteInline` | derived from `DiffDelete` | Adaptive inline background for the changed range  |

## Credits

- Heavily inspired by [vim-mundo](https://github.com/simnalamburt/vim-mundo)
- Refer to user commands implementation in [nvim-best-practices](https://github.com/nvim-neorocks/nvim-best-practices)
- The inline diff and syntax highlighting architecture draws inspiration from [diffs.nvim](https://github.com/barrettruth/diffs.nvim)
