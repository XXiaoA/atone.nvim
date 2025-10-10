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

--- position the cursor at a specific undo node in the tree graph
---@param id integer
local function set_cursor(id)
    if id <= 0 then
        api.nvim_win_set_cursor(_tree_win, { tree.total * 2 + 1, 0 }) -- root node
    elseif id <= tree.total then
        local lnum = (tree.total - id) * 2 + 1
        local column = tree.nodes[id].depth * 2 - 1
        column = vim.str_byteindex(tree.lines[lnum], "utf-16", column - 1) + 1
        api.nvim_win_set_cursor(_tree_win, { lnum, column })
    end
end

---@param n integer
local function undo_to(n)
    api.nvim_buf_call(M.attach_buf, function()
        vim.cmd("silent undo " .. n)
    end)
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
            --  2 * (total - id) + 1 = line
            local id_under_cursor = tree.total - (api.nvim_win_get_cursor(_tree_win)[1] - 1) / 2
            if id_under_cursor % 1 ~= 0 or not config.opts.diff_cur_node.enabled then
                return
            end
            vim.schedule(function()
                local before_ctx = diff.get_context(M.attach_buf, id_under_cursor - 1)
                local cur_ctx = diff.get_context(M.attach_buf, id_under_cursor)
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
        local id_under_cursor = math.ceil(tree.total - (api.nvim_win_get_cursor(_tree_win)[1] - 1) / 2)
        set_cursor(id_under_cursor - vim.v.count1)
    end, { buffer = _tree_buf })
    utils.keymap("n", "k", function()
        local id_under_cursor = math.floor(tree.total - (api.nvim_win_get_cursor(_tree_win)[1] - 1) / 2)
        set_cursor(id_under_cursor + vim.v.count1)
    end, { buffer = _tree_buf })
    utils.keymap("n", "<CR>", function()
        local id_under_cursor = api.nvim_get_current_line():match("%[(%d+)%]")
        if id_under_cursor then
            undo_to(id_under_cursor)
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
            _diff_win = utils.new_win("belowright split", _auto_diff_buf, { height = height }, false) -- TODO: height
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

        local cur_line = (tree.total - tree.cur_id) * 2 + 1
        utils.color_char(
            _tree_buf,
            "AtoneCurrentNode",
            buf_lines[cur_line],
            cur_line,
            tree.node_at(tree.cur_id).depth * 2 - 1 -- use node_at() because we maybe go to the original node
        )

        local before_ctx = diff.get_context(M.attach_buf, tree.cur_id - 1)
        local cur_ctx = diff.get_context(M.attach_buf, tree.cur_id)
        local diff_ctx = diff.get_diff(before_ctx, cur_ctx)
        utils.set_text(_auto_diff_buf, diff_ctx)

        set_cursor(tree.cur_id)
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
        set_cursor(tree.cur_id)
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
