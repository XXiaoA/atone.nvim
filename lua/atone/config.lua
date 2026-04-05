local M = {}
M.opts = {
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
}

function M.merge_config(user_opts)
    user_opts = user_opts or {}
    M.opts = vim.tbl_deep_extend("force", M.opts, user_opts)
end

return M
