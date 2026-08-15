local M = {}
---@type AtoneConfig
M.opts = {
    layout = {
        direction = "left",
        --- adaptive: adapt to width of tree graph
        --- float < 1: width = vim.o.columns * value
        --- integer >= 1: absolute width
        width = 0.25,
    },
    -- diff for the node under cursor
    -- shown under the tree graph
    diff_cur_node = {
        enabled = true,
        --- The diff window's height is set to a specified percentage of the original (namely tree graph) window's height.
        split_percent = 0.3,
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
        persist_path = vim.fn.stdpath("data") .. "/atone_marks.json",
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
            undo = "u",
            redo = "<C-r>",
            set_sticky_ref = "=",
            float_diff = "gd",
        },
        auto_diff = {
            quit = { "<C-c>", "q" },
            help = { "?", "g?" },
            undo = "u",
            redo = "<C-r>",
            float_diff = "gd",
        },
        help = {
            quit_help = { "<C-c>", "q" },
        },
    },
    diff_float = {
        --- width of the diff float as a fraction of the editor width (0–1)
        width = 0.8,
        --- height of the diff float as a fraction of the editor height (0–1)
        height = 0.8,
        --- close the centred diff float when it loses focus.
        autoclose = true,
    },
    ui = {
        -- refer to `:h 'winborder'`
        border = "single",
        -- compact graph style
        compact = false,
        -- Draw the undo tree with git branch drawing symbols (U+F5D0-U+F60D).
        -- Requires kitty >= 0.36.2, wezterm >= 2025-04-15 or ghostty >= 1.0.
        branch_symbols = false,
        node_label = {
            custom = false,
            ---@param ctx AtoneNodeLabelContext
            ---@return AtoneNodeLabel
            formatter = function(ctx)
                return string.format(
                    "[%d] %s %s%s",
                    ctx.seq,
                    ctx.h_time,
                    ctx.bookmark or "",
                    ctx.is_sticky_ref and " [=]" or ""
                )
            end,
            extmark_opts = { strict = false },
        },
    },
}

---@type table<string, AtoneGraphSymbols>
local symbol_sets = {
    default = {
        node = "●",
        vline = "│",
        hline = "─",
        fork = "├",
        merge = "┴",
        corner = "╯",
    },
    branch = {
        node = "",
        vline = "",
        hline = "",
        fork = "",
        merge = "",
        corner = "", -- upper-left arc
        -- Dynamic node glyphs: each node picks the glyph matching its actual connections instead of a plain dot.
        -- Keys are bit masks of the connections: up = 1, down = 2, left = 4, right = 8.
        node_glyphs = {
            [0] = "", -- no connections
            [1] = "", -- up
            [2] = "", -- down
            [3] = "", -- up + down
            [4] = "", -- left
            [5] = "", -- up + left
            [6] = "", -- down + left
            [7] = "", -- up + down + left
            [8] = "", -- right
            [9] = "", -- up + right
            [10] = "", -- down + right
            [11] = "", -- up + down + right
            [12] = "", -- left + right
            [13] = "", -- up + left + right
            [14] = "", -- down + left + right
            [15] = "", -- up + down + left + right
        },
    },
}

--- Resolve the graph symbol set from `ui.branch_symbols`.
---@return AtoneGraphSymbols
function M.get_graph_symbols()
    return M.opts.ui.branch_symbols and symbol_sets.branch or symbol_sets.default
end

---@param user_opts? AtoneConfig
function M.merge_config(user_opts)
    user_opts = user_opts or {}
    M.opts = vim.tbl_deep_extend("force", M.opts, user_opts)
end

return M
