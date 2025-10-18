local api, fn = vim.api, vim.fn
local diff = require("atone.diff")
local config = require("atone.config")
local tree = require("atone.tree")
local utils = require("atone.utils")

local M = {
    _show = nil,
    attach_buf = nil,
    augroup = api.nvim_create_augroup("atone", { clear = true }),
}
-- _float_win: we have one float window only at the same time
-- _manual_diff_buf: diff result between current and given point (triggered by user), shown in float window
-- _auto_diff_buf: diff result triggered automatically, shown in the window below tree graph
local _tree_win, _float_win, _diff_win, _tree_buf, _help_buf, _manual_diff_buf, _auto_diff_buf

--- position the cursor at a specific node in the tree graph
---@param id integer
local function pos_cursor_by_id(id)
    if id <= 0 then
        api.nvim_win_set_cursor(_tree_win, { tree.total * 2 - 1, 0 })
    elseif id <= tree.total then
        local lnum = (tree.total - id) * 2 + 1
        local column = tree.nodes[tree.id_2seq(id)].depth * 2 - 1
        column = vim.str_byteindex(tree.lines[lnum], "utf-16", column - 1)
        api.nvim_win_set_cursor(_tree_win, { lnum, column })
    end
end

---@param seq integer
local function undo_to(seq)
    api.nvim_buf_call(M.attach_buf, function()
        vim.cmd("silent undo " .. seq)
    end)
end

--- get the id under cursor in _tree_win
--- when the cursor is between two nodes, return the average (of their id).
---@return integer
local function id_under_cursor()
    --  2 * (last_id - cur_id) + 1 = lnum
    return tree.total - (api.nvim_win_get_cursor(_tree_win)[1] - 1) / 2
end

--- get the seq under cursor in _tree_win
--- when the cursor is between two nodes, return nil
---@return integer|nil
local function seq_under_cursor()
    local id = id_under_cursor()
    if id % 1 ~= 0 then
        return nil
    end
    return tree.id_2seq(id)
end

local used_mappings = {}
local mappings = {
    quit = {
        function()
            M.close()
        end,
        "Close all atone windows",
    },
    quit_help = {
        function()
            pcall(api.nvim_win_close, _float_win, true)
        end,
        "Close help window",
    },
    next_node = {
        function()
            pos_cursor_by_id(math.ceil(id_under_cursor()) - vim.v.count1)
        end,
        "Jump to next node (v:count supported)",
    }, -- support v:count
    pre_node = {
        function()
            pos_cursor_by_id(math.floor(id_under_cursor()) + vim.v.count1)
        end,
        "Jump to previous node (v:count supported)",
    }, -- support v:count
    undo_to = {
        function()
            local seq = seq_under_cursor()
            if seq then
                undo_to(seq)
                M.refresh()
            end
        end,
        "Undo to the node under cursor",
    },
    help = {
        function()
            M.show_help()
        end,
        "Show help page",
    },
}

local function init()
    _tree_buf = utils.new_buf()
    _auto_diff_buf = utils.new_buf()
    _help_buf = utils.new_buf()
    if config.opts.diff_cur_node.enabled then
        api.nvim_set_option_value("syntax", "diff", { buf = _auto_diff_buf })
    end

    api.nvim_create_autocmd("CursorMoved", {
        buffer = _tree_buf,
        group = M.augroup,
        callback = function()
            if not seq_under_cursor() or not config.opts.diff_cur_node.enabled then
                return
            end
            vim.schedule(function()
                local pre_seq = tree.nodes[seq_under_cursor()].parent or -1
                local before_ctx = diff.get_context_by_seq(M.attach_buf, pre_seq)
                ---@diagnostic disable-next-line: param-type-mismatch
                local cur_ctx = diff.get_context_by_seq(M.attach_buf, seq_under_cursor())
                local diff_ctx = diff.get_diff(before_ctx, cur_ctx)
                utils.set_text(_auto_diff_buf, diff_ctx)
            end)
        end,
    })
    api.nvim_create_autocmd("WinClosed", {
        buffer = _tree_buf,
        group = M.augroup,
        callback = M.close,
    })
    api.nvim_create_autocmd("WinClosed", {
        buffer = _auto_diff_buf,
        group = M.augroup,
        callback = M.close,
    })

    -- register keymaps
    local keymaps_conf = config.opts.keymaps
    for action, lhs in pairs(keymaps_conf.tree) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = _tree_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.auto_diff) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = _auto_diff_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.help) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = _help_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
end

local function check()
    if api.nvim_buf_is_valid(_auto_diff_buf) and api.nvim_buf_is_valid(_tree_buf) and api.nvim_buf_is_valid(_help_buf) then
        return true
    end
    M.close()
    pcall(api.nvim_buf_delete, _tree_buf, { force = false })
    pcall(api.nvim_buf_delete, _auto_diff_buf, { force = false })
    pcall(api.nvim_buf_delete, _help_buf, { force = false })
end

function M.open()
    if M._show == nil or not check() then
        init()
    end

    if not M._show then
        M._show = true
        M.attach_buf = api.nvim_get_current_buf()
        local direction = config.opts.layout.direction == "left" and "topleft" or "botright"
        local width = config.opts.layout.width
        if width == "adaptive" then
            ---@diagnostic disable-next-line: cast-local-type
            width = nil -- resize the window in M.refresh()
        elseif width < 1 then
            width = math.floor(vim.o.columns * width + 0.5)
        else
            ---@diagnostic disable-next-line: param-type-mismatch
            width = math.floor(width)
        end
        _tree_win = utils.new_win(direction .. " vsplit", _tree_buf, { width = width })
        if config.opts.diff_cur_node.enabled then
            local height = math.floor(api.nvim_win_get_height(_tree_win) * config.opts.diff_cur_node.split_percent + 0.5)
            _diff_win = utils.new_win("belowright split", _auto_diff_buf, { height = height }, false)
        end

        api.nvim_win_call(_tree_win, function()
            fn.matchadd("AtoneIDBracket", [=[\v\[\d+\]]=])
            fn.matchadd("AtoneID", [=[\v\[\zs\d+\ze\]]=])
        end)
        M.refresh()
    else
        M.focus()
    end
end

function M.refresh()
    if M._show then
        tree.convert(M.attach_buf)
        local buf_lines = tree.render()
        if config.opts.layout.width == "adaptive" then
            api.nvim_win_set_config(_tree_win, { width = fn.strchars(buf_lines[1]) + 5 })
        end
        utils.set_text(_tree_buf, buf_lines)
        pos_cursor_by_id(tree.seq_2id(tree.cur_seq))

        local cur_line = api.nvim_win_get_cursor(_tree_win)[1]
        utils.color_char(
            _tree_buf,
            "AtoneCurrentNode",
            buf_lines[cur_line],
            cur_line,
            tree.nodes[tree.cur_seq].depth * 2 - 1 -- use node_at() because we maybe go to the original node
        )

        local pre_seq = tree.nodes[tree.cur_seq].parent or -1
        local before_ctx = diff.get_context_by_seq(M.attach_buf, pre_seq)
        local cur_ctx = diff.get_context_by_seq(M.attach_buf, tree.cur_seq)
        local diff_ctx = diff.get_diff(before_ctx, cur_ctx)
        utils.set_text(_auto_diff_buf, diff_ctx)
    end
end

function M.show_help()
    -- set context for help buffer
    local help_lines = {}
    local max_lhs = 0
    local max_line = 0
    for _, v in pairs(used_mappings) do
        local lhs = v[1]
        local desc = v[2]
        if type(lhs) == "table" then
            lhs = table.concat(lhs, "/")
        end
        max_lhs = math.max(max_lhs, vim.api.nvim_strwidth(lhs))
        max_line = math.max(max_line, #lhs + #desc)
        help_lines[#help_lines + 1] = lhs .. "\t" .. desc
    end
    max_line = max_line + max_lhs + 4
    api.nvim_set_option_value("vartabstop", tostring(max_lhs + 4), { buf = _help_buf })
    utils.set_text(_help_buf, help_lines)

    -- open help window
    local editor_columns = api.nvim_get_option_value("columns", {})
    local editor_lines = api.nvim_get_option_value("lines", {})
    _float_win = utils.new_win("float", _help_buf, {
        relative = "editor",
        row = math.max(0, (editor_lines - #help_lines) / 2),
        col = math.max(0, (editor_columns - max_line - 1) / 2),
        width = math.min(editor_columns, max_line + 1),
        height = math.min(editor_lines, #help_lines),
        zindex = 150,
        style = "minimal",
        border = config.opts.ui.border,
    })
end

function M.close()
    if M._show then
        M._show = false
        pcall(api.nvim_win_close, _tree_win, true)
        pcall(api.nvim_win_close, _diff_win, true)
        pcall(api.nvim_win_close, _float_win, true)
    end
end

function M.focus()
    if M._show then
        pos_cursor_by_id(tree.seq_2id(tree.cur_seq))
        api.nvim_set_current_win(_tree_win)
    end
end

function M.toggle()
    if M._show then
        M.close()
    else
        M.open()
    end
end

return M
