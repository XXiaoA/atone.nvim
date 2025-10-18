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

## Command

main command: `Atone`

subcommands: `toggle`, `open`, `close`, `focus`

## Configuration

Default configuration:

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

- `AtoneID`:  link to "Number"
- `AtoneCurrentNode`:  link to "Keyword"
- `AtoneIDBracket`:  link to "Comment"

## Credits

- Heavily inspired by [vim-mundo](https://github.com/simnalamburt/vim-mundo)
- Refer to user commands implementation in [nvim-best-practices](https://github.com/nvim-neorocks/nvim-best-practices)
