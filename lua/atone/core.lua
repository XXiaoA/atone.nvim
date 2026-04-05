local api, fn = vim.api, vim.fn
local diff = require("atone.diff")
local highlight = require("atone.highlight")
local config = require("atone.config")
local tree = require("atone.tree")
local mark = require("atone.mark")
local utils = require("atone.utils")

local M = {
    _show = nil,
    attach_buf = nil,
    augroup = api.nvim_create_augroup("atone", { clear = true }),
    _tree_win = nil,
    _float_win = nil,
    _diff_win = nil,
    _tree_buf = nil,
    _help_buf = nil,
    _auto_diff_buf = nil,
    _dummy_win = nil,
    _dummy_buf = nil,
}

local _resize_autocmd_registered = false

--- position the cursor at a specific node in the tree graph
---@param id integer
local function pos_cursor_by_id(id)
    local compact = config.opts.ui.compact
    if id <= 0 then
        api.nvim_win_set_cursor(M._tree_win, { compact and tree.total or tree.total * 2 - 1, 0 })
    elseif id <= tree.total then
        local lnum = compact and tree.total - id + 1 or (tree.total - id) * 2 + 1
        local column = tree.nodes[tree.id_2seq(id)].depth * 2 - 1
        column = vim.str_byteindex(tree.lines[lnum], "utf-16", column - 1)
        api.nvim_win_set_cursor(M._tree_win, { lnum, column })
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
    -- compact: total - cur_id + 1 = lnum
    -- otherwise: 2 * (total - cur_id) + 1 = lnum
    local lnum = api.nvim_win_get_cursor(M._tree_win)[1]
    return config.opts.ui.compact and tree.total - lnum + 1 or tree.total - (lnum - 1) / 2
end

--- get the seq under cursor in _tree_win
--- when the cursor is between two nodes, return nil
---@return integer|nil
local function get_seq_under_cursor()
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
            pcall(api.nvim_win_close, M._float_win, true)
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
    jump_to_G = {
        function()
            pos_cursor_by_id(tree.seq_2id(vim.v.count))
        end,
        "Jump to the node with the specified sequence number like G",
    },
    jump_to_gg = {
        function()
            local target_seq = vim.v.count == 0 and tree.last_seq or vim.v.count
            pos_cursor_by_id(tree.seq_2id(target_seq))
        end,
        "Jump to the node with the specified sequence number like gg",
    },
    undo_to = {
        function()
            local seq = get_seq_under_cursor()
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
    set_mark = {
        function()
            local seq = get_seq_under_cursor()
            if not seq then
                return
            end
            local filepath = utils.buf_filepath(M.attach_buf)
            local function ask(default_val)
                vim.ui.input({ prompt = "Mark name (N:name or N for slot): ", default = default_val }, function(input)
                    if not input or input == "" then
                        return
                    end
                    local name, slot = mark.parse_input(input)
                    if not name then
                        vim.notify("Atone: Slot must be a single digit (0-9)", vim.log.levels.WARN)
                        ask(input)
                        return
                    end
                    mark.set_mark(filepath, seq, name, slot)
                    M.refresh(true)
                end)
            end
            ask()
        end,
        "Set a mark on the node under cursor",
    },
    delete_mark = {
        function()
            local seq = get_seq_under_cursor()
            if not seq then
                return
            end
            local filepath = utils.buf_filepath(M.attach_buf)
            local seq_marks = mark.get_by_seq(filepath, seq)
            if #seq_marks == 0 then
                vim.notify("Atone: No marks on this node", vim.log.levels.INFO)
                return
            end
            if #seq_marks == 1 then
                mark.delete_mark(filepath, seq_marks[1].name)
                M.refresh(true)
            else
                local names = vim.tbl_map(function(m)
                    return m.name
                end, seq_marks)
                vim.ui.select(names, { prompt = "Delete mark: " }, function(_, idx)
                    if idx then
                        mark.delete_mark(filepath, seq_marks[idx].name)
                        M.refresh(true)
                    end
                end)
            end
        end,
        "Delete the mark on the node under cursor",
    },
    goto_mark = {
        function()
            local filepath = utils.buf_filepath(M.attach_buf)
            local ch = fn.getcharstr()
            if ch == "\27" then
                return
            end
            local digit = tonumber(ch)
            if digit and digit >= 0 and digit <= 9 then
                local m = mark.get_by_slot(filepath, digit)
                if m then
                    local id = tree.seq_2id(m.seq)
                    if id then
                        pos_cursor_by_id(id)
                    else
                        vim.notify("Atone: Mark target seq " .. m.seq .. " not found in tree", vim.log.levels.WARN)
                    end
                else
                    vim.notify("Atone: No mark in slot " .. digit, vim.log.levels.INFO)
                end
            end
        end,
        "Jump to a mark slot (0-9)",
    },
    delete_all_marks = {
        function()
            local filepath = utils.buf_filepath(M.attach_buf)
            local marks = mark.get_marks(filepath)
            if vim.tbl_isempty(marks) then
                vim.notify("Atone: No marks in this buffer", vim.log.levels.INFO)
                return
            end
            mark.delete_all_marks(filepath)
            M.refresh(true)
        end,
        "Delete all marks in current buffer",
    },
    mark_picker = {
        function()
            mark.pick(M.attach_buf, function(m)
                if m then
                    local id = tree.seq_2id(m.seq)
                    if id then
                        pos_cursor_by_id(id)
                    end
                end
            end)
        end,
        "Open mark picker",
    },
}

--- Update the diff display buffer and apply the extra diff preview layers.
---@param diff_lines string[]
local function update_diff_buf(diff_lines)
    utils.set_text(M._auto_diff_buf, diff_lines)
    local lang = config.opts.diff_cur_node.treesitter and highlight.get_lang(M.attach_buf) or nil
    local target_syntax = lang and "" or "diff"
    if vim.bo[M._auto_diff_buf].syntax ~= target_syntax then
        api.nvim_set_option_value("syntax", target_syntax, { buf = M._auto_diff_buf })
    end
    highlight.apply(M._auto_diff_buf, diff_lines, lang, {
        treesitter = config.opts.diff_cur_node.treesitter,
        inline_diff = config.opts.diff_cur_node.inline_diff,
    })
end

---@param direction string
---@return string
local function get_anchor(direction)
    return direction == "left" and "SW" or "SE"
end

---@param direction string
---@return integer
local function get_col(direction)
    if direction == "left" then
        return 0
    end
    return api.nvim_win_get_width(M._dummy_win)
end

---@param lines string[]?
---@return integer
local function compute_tree_width(lines)
    local width = config.opts.layout.width
    if width ~= "adaptive" then
        ---@diagnostic disable-next-line: param-type-mismatch
        return width < 1 and math.floor(vim.o.columns * width + 0.5) or math.floor(width)
    end

    lines = lines or api.nvim_buf_get_lines(M._tree_buf, 0, 1, false)
    local first_line = lines[1] or ""
    return fn.strdisplaywidth(first_line) + 10
end

local function compute_diff_height()
    return math.floor(api.nvim_win_get_height(M._tree_win) * config.opts.diff_cur_node.split_percent + 0.5)
end

local function uses_float_diff()
    return config.opts.diff_cur_node.enabled and config.opts.diff_cur_node.width ~= "adaptive"
end

local function resize_tree_window(lines)
    if not utils.win_exists(M._tree_win) then
        return
    end

    api.nvim_win_set_width(M._tree_win, compute_tree_width(lines))
end

local function pos_float_diff_win()
    if not M._show or not uses_float_diff() then
        return
    end
    if not (utils.win_exists(M._tree_win) and utils.win_exists(M._diff_win) and utils.win_exists(M._dummy_win)) then
        return
    end

    local diff_width_conf = config.opts.diff_cur_node.width

    local diff_width = diff_width_conf < 1 and math.floor(vim.o.columns * diff_width_conf + 0.5)
        ---@diagnostic disable-next-line: param-type-mismatch
        or math.floor(diff_width_conf)

    local col = get_col(config.opts.layout.direction)
    local anchor = get_anchor(config.opts.layout.direction)
    local height = compute_diff_height()

    api.nvim_win_set_height(M._dummy_win, height)
    api.nvim_win_set_config(M._diff_win, {
        width = math.max(1, diff_width),
        height = height,
        relative = "win",
        win = M._dummy_win,
        anchor = anchor,
        row = height - 1,
        col = col,
    })
end

local function init()
    for _, buf_key in ipairs({ "tree_buf", "auto_diff_buf", "help_buf", "dummy_buf" }) do
        local old_buf = M["_" .. buf_key]
        if old_buf and api.nvim_buf_is_valid(old_buf) then
            pcall(api.nvim_buf_delete, old_buf, { force = true })
        end
    end

    M._tree_buf = utils.new_buf()
    M._auto_diff_buf = utils.new_buf()
    M._help_buf = utils.new_buf()
    M._dummy_buf = nil

    api.nvim_create_autocmd("CursorMoved", {
        buffer = M._tree_buf,
        group = M.augroup,
        callback = vim.schedule_wrap(function()
            local seq = get_seq_under_cursor()
            if not seq or not config.opts.diff_cur_node.enabled then
                return
            end
            update_diff_buf(diff.get_diff_by_seq(M.attach_buf, seq))
        end),
    })

    api.nvim_create_autocmd("WinClosed", {
        buffer = M._tree_buf,
        group = M.augroup,
        callback = M.close,
    })
    api.nvim_create_autocmd("WinClosed", {
        buffer = M._auto_diff_buf,
        group = M.augroup,
        callback = M.close,
    })

    if not _resize_autocmd_registered then
        api.nvim_create_autocmd("WinResized", {
            group = M.augroup,
            callback = function()
                if M._show then
                    vim.schedule(function()
                        pos_float_diff_win()
                    end)
                end
            end,
        })
        _resize_autocmd_registered = true
    end

    -- register keymaps
    local keymaps_conf = config.opts.keymaps
    for action, lhs in pairs(keymaps_conf.tree) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = M._tree_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.auto_diff) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = M._auto_diff_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.help) do
        utils.keymap("n", lhs, mappings[action][1], { buffer = M._help_buf })
        used_mappings[action] = { lhs, mappings[action][2] }
    end
end

local function check()
    if
        not (
            api.nvim_buf_is_valid(M._auto_diff_buf)
            and api.nvim_buf_is_valid(M._tree_buf)
            and api.nvim_buf_is_valid(M._help_buf)
        )
    then
        M.close()
        return false
    end

    if uses_float_diff() and not api.nvim_buf_is_valid(M._dummy_buf) then
        M.close()
        return false
    end

    return true
end

function M.open()
    if M._show == nil or not check() then
        init()
    end

    if M._show then
        M.focus()
        return
    end

    M._show = true
    M.attach_buf = api.nvim_get_current_buf()

    local direction = config.opts.layout.direction == "left" and "topleft" or "botright"

    local width = compute_tree_width()
    M._tree_win = utils.new_win(direction .. " vsplit", M._tree_buf, { win_config = { width = width } })
    if config.opts.diff_cur_node.enabled then
        local height = compute_diff_height()
        local diff_width_conf = config.opts.diff_cur_node.width

        if uses_float_diff() then
            local diff_width = diff_width_conf < 1 and math.floor(vim.o.columns * diff_width_conf + 0.5)
                ---@diagnostic disable-next-line: param-type-mismatch
                or math.floor(diff_width_conf)

            if not (M._dummy_buf and api.nvim_buf_is_valid(M._dummy_buf)) then
                M._dummy_buf = utils.new_buf()
                api.nvim_create_autocmd("WinEnter", {
                    buffer = M._dummy_buf,
                    group = M.augroup,
                    callback = function()
                        if utils.win_exists(M._diff_win) then
                            api.nvim_set_current_win(M._diff_win)
                        end
                    end,
                })
            end
            M._dummy_win = utils.new_win("belowright split", M._dummy_buf, { win_config = { height = height } }, false)

            local anchor = get_anchor(config.opts.layout.direction)
            local col = get_col(config.opts.layout.direction)

            -- 'none', 'solid', and 'shadow' are handled specially or by fallback
            local BORDER_MAP = {
                single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
                double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
                rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
                bold = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
                solid = { " ", " ", " ", " ", " ", " ", " ", " " },
                shadow = { "", "", " ", " ", " ", " ", " ", "" },
            }
            local border = config.opts.ui.border
            local border_chars
            if type(border) == "string" and border ~= "none" then
                -- Fallback to 'single' if the string doesn't match our map
                local template = BORDER_MAP[border] or BORDER_MAP.single
                border_chars = { unpack(template) }
                -- Indices: 1:top-left, 2:top, 3:top-right, 4:right, 5:bottom-right, 6:bottom, 7:bottom-left, 8:left
                if config.opts.layout.direction == "left" then
                    -- Remove the left-side connectors for a seamless sidebar look
                    border_chars[6] = "" -- Bottom
                    border_chars[7] = "" -- Bottom-left
                    border_chars[8] = "" -- Left
                else
                    -- Remove the right-side connectors
                    border_chars[4] = "" -- Right
                    border_chars[5] = "" -- Bottom-right
                    border_chars[6] = "" -- Bottom
                end
            end

            M._diff_win = utils.new_win("float", M._auto_diff_buf, {
                win_config = {
                    relative = "win",
                    win = M._dummy_win,
                    anchor = anchor,
                    row = height - 1,
                    col = col,
                    width = diff_width,
                    height = height,
                    style = "minimal",
                    border = border_chars,
                    zindex = 150,
                },
            }, false)

            api.nvim_set_option_value("winhl", "Normal:Normal,FloatBorder:WinSeparator", { win = M._diff_win })
        else
            M._diff_win = utils.new_win("belowright split", M._auto_diff_buf, { win_config = { height = height } }, false)
        end
    end

    api.nvim_win_call(M._tree_win, function()
        fn.matchadd("AtoneSeqBracket", [=[\v\[\d+\]]=])
        fn.matchadd("AtoneSeq", [=[\v\[\zs\d+\ze\]]=])
        fn.matchadd("AtoneMark", [=[\v\{[^}]+\}]=])
    end)
    M.refresh()
end

---@param stay boolean?
function M.refresh(stay)
    if M._show then
        tree.convert(M.attach_buf)
        local filepath = utils.buf_filepath(M.attach_buf)
        mark.prune(filepath, tree.nodes)
        local marks_labels = mark.build_labels(filepath)
        local buf_lines = tree.render(marks_labels)
        utils.set_text(M._tree_buf, buf_lines)
        resize_tree_window(buf_lines)

        if config.opts.diff_cur_node.width ~= "adaptive" then
            pos_float_diff_win()
        end

        if not stay then
            pos_cursor_by_id(tree.seq_2id(tree.cur_seq))
        end

        local compact = config.opts.ui.compact
        local id = tree.seq_2id(tree.cur_seq)
        local cur_line = compact and tree.total - id + 1 or (tree.total - id) * 2 + 1
        utils.color_char(
            M._tree_buf,
            "AtoneCurrentNode",
            buf_lines[cur_line],
            cur_line,
            tree.nodes[tree.cur_seq].depth * 2 - 1
        )

        if config.opts.diff_cur_node.enabled then
            update_diff_buf(diff.get_diff_by_seq(M.attach_buf, tree.cur_seq))
        end
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
    api.nvim_set_option_value("vartabstop", tostring(max_lhs + 4), { buf = M._help_buf })
    utils.set_text(M._help_buf, help_lines)

    -- open help window
    local editor_columns = api.nvim_get_option_value("columns", {})
    local editor_lines = api.nvim_get_option_value("lines", {})
    M._float_win = utils.new_win("float", M._help_buf, {
        win_config = {
            relative = "editor",
            row = math.max(0, (editor_lines - #help_lines) / 2),
            col = math.max(0, (editor_columns - max_line - 1) / 2),
            width = math.min(editor_columns, max_line + 1),
            height = math.min(editor_lines, #help_lines),
            zindex = 150,
            style = "minimal",
            border = config.opts.ui.border,
        },
        autoclose = true,
    })
end

function M.close()
    if M._show then
        M._show = false
        pcall(api.nvim_win_close, M._tree_win, true)
        pcall(api.nvim_win_close, M._diff_win, true)
        pcall(api.nvim_win_close, M._float_win, true)
        pcall(api.nvim_win_close, M._dummy_win, true)
    end
end

function M.focus()
    if M._show then
        pos_cursor_by_id(tree.seq_2id(tree.cur_seq))
        api.nvim_set_current_win(M._tree_win)
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
