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
        column = vim.str_byteindex(tree.lines[lnum], "utf-16", column - 1) + 1
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

local function init()
    _tree_buf = utils.new_buf()
    _auto_diff_buf = utils.new_buf()
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
                local pre_seq = tree.id_2seq(id_under_cursor() - 1) or -1
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

    utils.keymap("n", "q", M.close, { buffer = _tree_buf })
    utils.keymap("n", "q", M.close, { buffer = _auto_diff_buf })
    utils.keymap("n", "j", function()
        pos_cursor_by_id(math.ceil(id_under_cursor()) - vim.v.count1)
    end, { buffer = _tree_buf })
    utils.keymap("n", "k", function()
        pos_cursor_by_id(math.floor(id_under_cursor()) + vim.v.count1)
    end, { buffer = _tree_buf })
    utils.keymap("n", "<CR>", function()
        local seq = seq_under_cursor()
        if seq then
            undo_to(seq)
            M.refresh()
        end
    end, { buffer = _tree_buf })
end

local function check()
    if api.nvim_buf_is_valid(_auto_diff_buf) and api.nvim_buf_is_valid(_tree_buf) then
        return true
    end
    M.close()
    pcall(api.nvim_buf_delete, _tree_buf, false)
    pcall(api.nvim_buf_delete, _auto_diff_buf, false)
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

        local pre_id = tree.seq_2id(tree.cur_seq) - 1
        local pre_seq = tree.id_2seq(pre_id) or -1
        local before_ctx = diff.get_context_by_seq(M.attach_buf, pre_seq)
        local cur_ctx = diff.get_context_by_seq(M.attach_buf, tree.cur_seq)
        local diff_ctx = diff.get_diff(before_ctx, cur_ctx)
        utils.set_text(_auto_diff_buf, diff_ctx)
    end
end

function M.close()
    if M._show then
        M._show = false
        pcall(api.nvim_win_close, _tree_win, true)
        pcall(api.nvim_win_close, _diff_win, true)
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
