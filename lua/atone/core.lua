local api, fn = vim.api, vim.fn
local diff = require("atone.diff")
local highlight = require("atone.highlight")
local config = require("atone.config")
local tree = require("atone.tree")
local mark = require("atone.mark")
local actions = require("atone.actions")
local utils = require("atone.utils")

local M = {
    _show = nil,
    attach_buf = nil,
    augroup = api.nvim_create_augroup("atone", { clear = true }),
    _tree_win = nil,
    _float_win = nil,
    _diff_win = nil,
    _centered_diff_win = nil,
    _tree_buf = nil,
    _help_buf = nil,
    _auto_diff_buf = nil,
    _centered_diff_buf = nil,
    _dummy_win = nil,
    _dummy_buf = nil,
    _sticky_ref = nil,
}

local _resize_autocmd_registered = false

--- position the cursor at a specific node in the tree graph
---@param id integer
function M.pos_cursor_by_id(id)
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

--- get the id under cursor in _tree_win
--- when the cursor is between two nodes, return the average (of their id).
---@return integer
function M.id_under_cursor()
    -- compact: total - cur_id + 1 = lnum
    -- otherwise: 2 * (total - cur_id) + 1 = lnum
    local lnum = api.nvim_win_get_cursor(M._tree_win)[1]
    return config.opts.ui.compact and tree.total - lnum + 1 or tree.total - (lnum - 1) / 2
end

--- get the seq under cursor in _tree_win
--- when the cursor is between two nodes, return nil
---@return integer|nil
function M.get_seq_under_cursor()
    local id = M.id_under_cursor()
    if id % 1 ~= 0 then
        return nil
    end
    return tree.id_2seq(id)
end

---@param buf integer
---@param diff_lines string[]
local function render_diff_buf(buf, diff_lines)
    utils.set_text(buf, diff_lines)
    local lang = config.opts.diff_cur_node.treesitter and highlight.get_lang(M.attach_buf) or nil
    local target_syntax = lang and "" or "diff"
    if vim.bo[buf].syntax ~= target_syntax then
        api.nvim_set_option_value("syntax", target_syntax, { buf = buf })
    end
    highlight.apply(buf, diff_lines, lang, {
        treesitter = config.opts.diff_cur_node.treesitter,
        inline_diff = config.opts.diff_cur_node.inline_diff,
    })
end

--- Prepend a `[old] → [new]` header line to a diff buffer when a sticky ref is set.
---@param buf integer
---@param seq integer|nil
local function apply_sticky_ref_header(buf, seq)
    local ns = api.nvim_create_namespace("atone_diff_header")
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if M._sticky_ref ~= nil and seq ~= nil then
        local header = string.format("[%d] → [%d]", M._sticky_ref, seq)
        -- Prepend as a real line; existing highlight extmarks shift automatically
        utils.set_text(buf, { header }, 0, 0)
        api.nvim_buf_set_extmark(buf, ns, 0, 0, {
            end_row = 0,
            end_col = #header,
            hl_group = "Comment",
            hl_eol = true,
        })
    end
end

---@param seq integer|nil
function M.update_diff_views(seq)
    if not seq then
        return
    end
    local diff_lines
    if M._sticky_ref ~= nil then
        local old = diff.get_context_by_seq(M.attach_buf, M._sticky_ref)
        local new = diff.get_context_by_seq(M.attach_buf, seq)
        diff_lines = diff.get_diff(old, new)
    else
        diff_lines = diff.get_diff_by_seq(M.attach_buf, seq)
    end
    if config.opts.diff_cur_node.enabled then
        render_diff_buf(M._auto_diff_buf, diff_lines)
        apply_sticky_ref_header(M._auto_diff_buf, seq)
        if M._sticky_ref ~= nil and M._diff_win and api.nvim_win_is_valid(M._diff_win) then
            api.nvim_win_set_cursor(M._diff_win, { 1, 0 })
        end
    end
    if M._centered_diff_buf and api.nvim_buf_is_valid(M._centered_diff_buf) then
        render_diff_buf(M._centered_diff_buf, diff_lines)
        apply_sticky_ref_header(M._centered_diff_buf, seq)
    end
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

---@return boolean?
local function uses_floating_preview_diff()
    return config.opts.diff_cur_node.enabled and config.opts.diff_cur_node.width ~= "adaptive"
end

local function compute_diff_height()
    local height = api.nvim_win_get_height(M._tree_win)

    if uses_floating_preview_diff() and utils.win_exists(M._dummy_win) then
        -- The hidden dummy split lives below the tree window and consumes one
        -- separator row, so include both pieces to recover the full column height.
        height = height + api.nvim_win_get_height(M._dummy_win) + 1
    end

    return math.max(1, math.floor(height * config.opts.diff_cur_node.split_percent + 0.5))
end

local function resize_tree_window(lines)
    if not utils.win_exists(M._tree_win) then
        return
    end

    api.nvim_win_set_width(M._tree_win, compute_tree_width(lines))
end

local function pos_floating_preview_diff_win()
    if not M._show or not uses_floating_preview_diff() then
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
        row = height,
        col = col,
    })
end

local function init()
    for _, buf_key in ipairs({ "tree_buf", "auto_diff_buf", "centered_diff_buf", "help_buf", "dummy_buf" }) do
        local old_buf = M["_" .. buf_key]
        if old_buf and api.nvim_buf_is_valid(old_buf) then
            pcall(api.nvim_buf_delete, old_buf, { force = true })
        end
    end

    M._tree_buf = utils.new_buf()
    M._auto_diff_buf = utils.new_buf()
    M._centered_diff_buf = utils.new_buf()
    M._help_buf = utils.new_buf()
    M._dummy_buf = nil

    api.nvim_create_autocmd("CursorMoved", {
        buffer = M._tree_buf,
        group = M.augroup,
        callback = vim.schedule_wrap(function()
            local seq = M.get_seq_under_cursor()
            if not seq then
                return
            end
            if not config.opts.diff_cur_node.enabled and not utils.win_exists(M._centered_diff_win) then
                return
            end
            M.update_diff_views(seq)
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

    api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
        buffer = M._tree_buf,
        group = M.augroup,
        callback = function()
            if not config.opts.ui.node_label.custom then
                return
            end
            if not M._show or not (utils.win_exists(M._tree_win) and api.nvim_buf_is_valid(M._tree_buf)) then
                return
            end
            tree.render_visible_labels(M._tree_buf, M._tree_win)
        end,
    })

    if not _resize_autocmd_registered then
        api.nvim_create_autocmd("WinResized", {
            group = M.augroup,
            callback = function()
                if M._show then
                    vim.schedule(function()
                        pos_floating_preview_diff_win()
                    end)
                end
            end,
        })
        _resize_autocmd_registered = true
    end

    -- register keymaps
    local keymaps_conf = config.opts.keymaps
    for action, lhs in pairs(keymaps_conf.tree) do
        utils.keymap("n", lhs, actions.actions[action][1], { buffer = M._tree_buf })
        actions.used_mappings[action] = { lhs, actions.actions[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.auto_diff) do
        utils.keymap("n", lhs, actions.actions[action][1], { buffer = M._auto_diff_buf })
        actions.used_mappings[action] = { lhs, actions.actions[action][2] }
    end
    for action, lhs in pairs(keymaps_conf.help) do
        utils.keymap("n", lhs, actions.actions[action][1], { buffer = M._help_buf })
        actions.used_mappings[action] = { lhs, actions.actions[action][2] }
    end
end

local function check()
    if
        not (
            api.nvim_buf_is_valid(M._auto_diff_buf)
            and api.nvim_buf_is_valid(M._centered_diff_buf)
            and api.nvim_buf_is_valid(M._tree_buf)
            and api.nvim_buf_is_valid(M._help_buf)
        )
    then
        M.close()
        return false
    end

    if uses_floating_preview_diff() and not (M._dummy_buf and api.nvim_buf_is_valid(M._dummy_buf)) then
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

        if uses_floating_preview_diff() then
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
                    row = height,
                    col = col,
                    width = diff_width,
                    height = height,
                    style = "minimal",
                    border = border_chars,
                    zindex = 50,
                },
            }, false)

            api.nvim_set_option_value("winhl", "Normal:Normal,FloatBorder:WinSeparator", { win = M._diff_win })
        else
            M._diff_win = utils.new_win("belowright split", M._auto_diff_buf, { win_config = { height = height } }, false)
        end
    end

    if not config.opts.ui.node_label.custom then
        api.nvim_win_call(M._tree_win, function()
            fn.matchadd("AtoneSeqBracket", [=[\v\[\d+\]]=])
            fn.matchadd("AtoneSeq", [=[\v\[\zs\d+\ze\]]=])
            fn.matchadd("AtoneMark", [=[\v\{[^}]+\}]=])
            fn.matchadd("AtoneStickyRef", [=[\v\[\=\]]=])
        end)
    end
    M.refresh()
end

---@param stay boolean?
function M.refresh(stay)
    if M._show then
        tree.convert(M.attach_buf)
        if M._sticky_ref and not tree.nodes[M._sticky_ref] then
            M._sticky_ref = nil
        end
        local filepath = utils.buf_filepath(M.attach_buf)
        mark.prune(filepath, tree.nodes)
        local marks_labels = mark.build_labels(filepath)
        local buf_lines = tree.render(marks_labels, M._sticky_ref)
        utils.set_text(M._tree_buf, buf_lines)
        api.nvim_buf_clear_namespace(M._tree_buf, api.nvim_create_namespace("atone"), 0, -1)
        if config.opts.ui.node_label.custom then
            tree.render_visible_labels(M._tree_buf, M._tree_win)
        end
        resize_tree_window(buf_lines)

        if config.opts.diff_cur_node.width ~= "adaptive" then
            pos_floating_preview_diff_win()
        end

        if not stay then
            M.pos_cursor_by_id(tree.seq_2id(tree.cur_seq))
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

        if M._sticky_ref and tree.nodes[M._sticky_ref] then
            local sticky_id = tree.seq_2id(M._sticky_ref)
            if sticky_id then
                local sticky_lnum = compact and tree.total - sticky_id + 1 or (tree.total - sticky_id) * 2 + 1
                utils.color_char(
                    M._tree_buf,
                    "AtoneStickyRef",
                    buf_lines[sticky_lnum],
                    sticky_lnum,
                    tree.nodes[M._sticky_ref].depth * 2 - 1
                )
            end
        end

        M.update_diff_views(M.get_seq_under_cursor() or tree.cur_seq)
    end
end

function M.show_help()
    -- set context for help buffer
    local help_lines = {}
    local max_lhs = 0
    local max_line = 0
    for _, v in pairs(actions.used_mappings) do
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
        M._sticky_ref = nil
        pcall(api.nvim_win_close, M._tree_win, true)
        pcall(api.nvim_win_close, M._diff_win, true)
        pcall(api.nvim_win_close, M._float_win, true)
        pcall(api.nvim_win_close, M._dummy_win, true)
        pcall(api.nvim_win_close, M._centered_diff_win, true)
    end
end

function M.focus()
    if M._show then
        M.pos_cursor_by_id(tree.seq_2id(tree.cur_seq))
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
