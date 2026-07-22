local api, fn = vim.api, vim.fn
local config = require("atone.config")
local utils = require("atone.utils")

local get_diff_by_seq = require("atone.diff").get_diff_by_seq
local get_diff_by_seq_cached = utils.cache(get_diff_by_seq)
local get_diff_stats_cached = utils.cache(function(bufnr, seq)
    local diff_patch = get_diff_by_seq_cached(bufnr, seq)

    ---@type AtoneNodeLabelContextDiff
    local diff_stats = { added = 0, removed = 0 }
    for _, line in ipairs(diff_patch) do
        local prefix = line:sub(1, 1)
        if prefix == "+" then
            diff_stats.added = diff_stats.added + 1
        elseif prefix == "-" then
            diff_stats.removed = diff_stats.removed + 1
        end
    end

    return diff_stats
end)

--- Get the character at column `col` (1-based character index).
---@param line string
---@param col integer 1-based character column
---@return string
local function get_char(line, col)
    return fn.strcharpart(line, col - 1, 1)
end

--- Replace the character at position `pos` (1-based character index) with `ch`.
---@param str string
---@param pos integer 1-based character column
---@param ch string
local function set_char_at(str, pos, ch)
    local len = fn.strchars(str)
    if pos > len then
        return str .. string.rep(" ", pos - len - 1) .. ch
    else
        return fn.strcharpart(str, 0, pos - 1) .. ch .. fn.strcharpart(str, pos)
    end
end

local M = {
    attach_buf = nil,
    ---@type table<integer, AtoneNode>
    --- { seq: node } mapping
    nodes = {},
    lines = {},
    -- Maps rendered tree line numbers back to undo seq so visible-label refresh can
    -- update only the rows that actually contain nodes.
    lnum_to_seq = {},
    marks_labels = {},
    sticky_ref = nil,
    total = 1,
    last_seq = 0,
    cur_seq = 0,
}

local extmark_meta = {
    col = nil,
    ns = api.nvim_create_namespace("atone_tree_label"),
    topline = nil,
    botline = nil,
}
---@param node AtoneNode
---@return string
local function get_h_time(node)
    return node.seq > 0 and node.time ~= nil and utils.time_ago(node.time) or "Original"
end

---@param node AtoneNode
---@return AtoneNodeLabel
local function get_node_label(node)
    local ctx = {
        seq = node.seq,
        is_current = node.seq == M.cur_seq,
        is_sticky_ref = node.seq == M.sticky_ref,
        time = node.time,
        h_time = get_h_time(node),
        bookmark = M.marks_labels[node.seq],
        diff = function()
            return get_diff_stats_cached(M.attach_buf, node.seq)
        end,
    }

    -- Keep `diff` lazy so simple formatters don't pay for reconstructing undo snapshots.
    local label = config.opts.ui.node_label.formatter(setmetatable({}, {
        __index = function(_, k)
            ---@type boolean|string|integer|function
            local val = ctx[k]
            if type(val) == "function" then
                -- allows on-demand of the diff stats
                val = val() ---@cast val -function
            end
            return val
        end,
    }))

    if type(label) == "string" then
        return label
    end
    if type(label) ~= "table" then
        return tostring(label)
    end

    ---@type AtoneNodeLabelChunk[]
    local items = {}
    for _, item in ipairs(label) do
        if type(item) == "table" then
            items[#items + 1] = { tostring(item[1]), item[2] or "Normal" }
        else
            items[#items + 1] = { tostring(item), "Normal" }
        end
    end
    return items
end

---@param lnum integer
---@return string, {start_col: integer, end_col: integer, hl_group: string}[]?
local function build_display_line(lnum)
    local line = M.lines[lnum] or ""
    local seq = M.lnum_to_seq[lnum]
    if seq == nil then
        return line, nil
    end

    local node = M.nodes[seq]
    if not node then
        return line, nil
    end

    local label = node.label or get_node_label(node)
    node.label = label
    if type(label) == "string" then
        return set_char_at(line, extmark_meta.col, label), nil
    end

    -- Chunk labels are flattened into buffer text first, then highlighted with
    -- extmark ranges. That avoids depending on virt_text for the label itself.
    local parts = {}
    for _, chunk in ipairs(label) do
        parts[#parts + 1] = chunk[1]
    end
    local display_line = set_char_at(line, extmark_meta.col, table.concat(parts))
    local spans = {}
    local col_offset = 0
    for _, chunk in ipairs(label) do
        local text = chunk[1]
        local hl_group = chunk[2]
        local width = fn.strchars(text)
        if hl_group and hl_group ~= "" and hl_group ~= "Normal" and width > 0 then
            spans[#spans + 1] = {
                start_col = vim.str_byteindex(display_line, "utf-16", extmark_meta.col - 1 + col_offset),
                end_col = vim.str_byteindex(display_line, "utf-16", extmark_meta.col - 1 + col_offset + width),
                hl_group = hl_group,
            }
        end
        col_offset = col_offset + width
    end

    return display_line, spans
end

local seqs -- { id: seq }
local ids -- { seq: id }
function M.id_2seq(id)
    return seqs[id]
end
function M.seq_2id(seq)
    return ids[seq]
end

function M.change_branch_depth(node_seq, new_depth_baseline)
    local depth_difference = new_depth_baseline - M.nodes[node_seq].depth
    local queue = { node_seq }
    local head, tail = 1, 1
    while head <= tail do
        local node = M.nodes[queue[head]]
        node.depth = node.depth + depth_difference
        local children = node.children
        for i = 1, #children do
            tail = tail + 1
            queue[tail] = children[i]
        end
        head = head + 1
    end
end

function M.convert(buf)
    M.attach_buf = buf
    local undotree = fn.undotree(buf)

    -- initiate
    M.nodes = {}
    M.nodes[0] = {
        seq = 0,
        depth = 1,
        -- child is a descendant with the same depth as the node.
        child = nil,
        children = {},
    }
    M.cur_seq = undotree.seq_cur
    M.last_seq = undotree.seq_last
    if M.last_seq == 0 then
        return M.nodes
    end

    local earliest_seq = undotree.entries[1].seq
    local function flatten(rawtree, parent)
        for _, raw_node in ipairs(rawtree) do
            ---@diagnostic disable-next-line: missing-fields
            M.nodes[raw_node.seq] = {
                seq = raw_node.seq,
                time = raw_node.time,
                parent = parent, -- 0 means the root node
                children = {},
            }
            if raw_node.alt then
                flatten(raw_node.alt, parent)
            end
            parent = raw_node.seq
            if raw_node.seq < earliest_seq then
                earliest_seq = raw_node.seq
            end
        end
    end
    flatten(undotree.entries, 0)

    -- set the depth: the depth of each branch depth = the depth of its root node's parent node plus 1
    -- determine the main branch with a depth of 1
    do
        local seq = undotree.seq_last
        repeat
            local node = M.nodes[seq]
            node.depth = 1
            seq = node.parent
        until seq == 0
    end
    -- fill in depths for other branches
    for seq = M.last_seq - 1, earliest_seq, -1 do
        if M.nodes[seq] and not M.nodes[seq].depth then
            local path = {}
            local sub_seq = seq
            local sub_node = M.nodes[sub_seq]
            repeat
                path[#path + 1] = sub_seq
                sub_seq = sub_node.parent
                sub_node = M.nodes[sub_seq]
            until sub_node.depth
            for _, i in ipairs(path) do
                M.nodes[i].depth = sub_node.depth + 1
            end
        end
    end

    for seq = M.last_seq, earliest_seq, -1 do
        local node = M.nodes[seq]
        if node then
            local parent_node = M.nodes[node.parent]
            parent_node.children[#parent_node.children + 1] = seq
            if node.depth == parent_node.depth then
                parent_node.child = seq
            end
        end
    end

    -- adjust the depth
    for seq = M.last_seq, earliest_seq + 1, -1 do
        local node = M.nodes[seq]
        if not node then
            goto continue
        end
        if node.depth ~= 1 and seq ~= node.parent + 1 and not node.fork then
            for sub_seq = seq - 1, node.parent + 1, -1 do
                local sub_node = M.nodes[sub_seq]
                if not sub_node then
                    goto continue
                end
                local sub_node_parent = M.nodes[sub_node.parent]
                if
                    sub_node.depth == node.depth
                    and sub_node.depth ~= sub_node_parent.depth
                    and (sub_node.parent ~= node.parent or seq > M.nodes[node.parent].child)
                then
                    if sub_seq < sub_node_parent.child then
                        sub_node.fork = true
                    end
                    M.change_branch_depth(sub_seq, sub_node.depth + 1)
                end
                ::continue::
            end
        end
        ::continue::
    end

    return M.nodes
end

-- we should reverse the table: put the node with greater id in the smaller index
--      seq  id  index                                                --      seq  id  index
-- @    [4]   5    1                                                  -- @    [4]   5    1
-- |               2                                                  -- | o  [3]   4    2
-- | o  [3]   4    3                                                  -- o |  [2]   3    3
-- | |             4                                                  -- o/   [1]   2    4
-- | o  [2]   3    5                                                  -- o    [0]   1    5
-- | |             6
-- o |  [1]   2    7  <- a node
-- |/              8  <- line after this node
-- o    [0]   1    9
function M.render(marks_labels, sticky_ref)
    marks_labels = marks_labels or {}
    M.marks_labels = marks_labels
    M.sticky_ref = sticky_ref
    M.lines = {}
    M.lnum_to_seq = {}
    local max_depth = 1

    seqs = { 0 }
    -- the order number of node. Root node's id is 1
    local id = 1
    -- total of nodes (including root)
    local total = 1
    while id <= total do
        local seq = seqs[id]
        local node = M.nodes[seq]
        if node.depth > max_depth then
            max_depth = node.depth
        end
        local children = node.children
        for i = 1, #children do
            total = total + 1
            seqs[total] = children[i]
        end
        id = id + 1
    end
    table.sort(seqs)

    ids = {}
    id = 1
    while id <= total do
        ids[seqs[id]] = id
        id = id + 1
    end

    M.total = total

    local compact = config.opts.ui.compact
    local root_lnum = compact and total or 2 * total - 1
    M.lines[root_lnum] = "●"
    M.lnum_to_seq[root_lnum] = 0
    id = 2
    while id <= total do
        local seq = seqs[id]
        local node = M.nodes[seq]
        local depth = node.depth
        local parent_depth = M.nodes[node.parent].depth
        local node_lnum = compact and total - id + 1 or (total - id) * 2 + 1
        M.lnum_to_seq[node_lnum] = seq
        if depth == 1 then
            M.lines[node_lnum] = "●"
        else
            M.lines[node_lnum] = "│" .. (" "):rep(node.depth * 2 - 3) .. "●"
        end
        if not compact then
            M.lines[node_lnum + 1] = "│" -- line after this node
        end
        if not node.fork and depth ~= 1 then
            local lnum_is_drawing = node_lnum + 1
            local parent_index = compact and total - M.seq_2id(node.parent) + 1 or (total - M.seq_2id(node.parent)) * 2 + 1 -- index of parent node
            while lnum_is_drawing < parent_index and get_char(M.lines[lnum_is_drawing], depth * 2 - 1) ~= "●" do
                if get_char(M.lines[lnum_is_drawing], depth * 2 - 1) ~= "├" then
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "│")
                end
                lnum_is_drawing = lnum_is_drawing + 1
            end
            if depth ~= parent_depth then
                if not compact or get_char(M.lines[lnum_is_drawing], depth * 2 - 1) == "●" then
                    lnum_is_drawing = lnum_is_drawing - 1
                end
                if get_char(M.lines[lnum_is_drawing], depth * 2) == "─" then
                    --  ●
                    --  │
                    --  │ ●
                    -- ─┴─╯
                    --  ^
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "┴")
                else
                    -- condition check for compact style graph
                    -- ●              ●
                    -- │ ●            ├─●
                    -- ├─╯    ->      ├─●
                    -- │ ●            │ ●
                    -- ●─╯            ●─╯
                    if not compact or get_char(M.lines[lnum_is_drawing], depth * 2 - 1) ~= "●" then
                        M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "╯")
                    end
                end
                for pos = parent_depth * 2, depth * 2 - 2 do
                    if get_char(M.lines[lnum_is_drawing], pos) == " " then
                        M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], pos, "─")
                    elseif get_char(M.lines[lnum_is_drawing], pos) == "╯" then
                        M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], pos, "┴")
                    end
                end
                if get_char(M.lines[lnum_is_drawing], parent_depth * 2 - 1) ~= "●" then
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], parent_depth * 2 - 1, "├")
                end
            end
        elseif node.fork then
            M.lines[node_lnum] = set_char_at(M.lines[node_lnum], parent_depth * 2 - 1, "├")
            for i = parent_depth * 2, depth * 2 - 2 do
                M.lines[node_lnum] = set_char_at(M.lines[node_lnum], i, "─")
            end
        end

        id = id + 1
    end

    local label_col = max_depth * 2 + 4
    extmark_meta.col = label_col
    extmark_meta.topline = nil
    extmark_meta.botline = nil

    if not config.opts.ui.node_label.custom then
        for i = 1, total do
            local seq = M.id_2seq(i)
            local lnum = compact and total - i + 1 or (total - i) * 2 + 1
            local node = M.nodes[seq]
            local sticky = seq == M.sticky_ref and " [=]" or ""
            M.lines[lnum] = set_char_at(
                M.lines[lnum],
                label_col,
                string.format("[%s] %s %s%s", seq, get_h_time(node), marks_labels[seq] or "", sticky)
            )
        end
    end

    return M.lines
end

---@param bufnr integer
---@param winid integer
function M.render_visible_labels(bufnr, winid)
    if not config.opts.ui.node_label.custom then
        return
    end
    if not bufnr or not api.nvim_buf_is_valid(bufnr) then
        return
    end

    if not winid or not api.nvim_win_is_valid(winid) then
        return
    end

    local wininfo = fn.getwininfo(winid)[1]
    if not wininfo then
        return
    end

    local topline = wininfo.topline or 1
    local botline = wininfo.botline or (topline + (wininfo.height or api.nvim_win_get_height(winid)) - 1)
    topline = math.max(1, topline)
    botline = math.min(botline, #M.lines)
    if topline > botline then
        return
    end

    -- If the new viewport stays inside the last painted range, the existing label
    -- text is still valid and we can skip touching the buffer.
    if
        extmark_meta.topline
        and extmark_meta.botline
        and topline >= extmark_meta.topline
        and botline <= extmark_meta.botline
    then
        return
    end

    if extmark_meta.topline and extmark_meta.botline and extmark_meta.topline <= extmark_meta.botline then
        local lines = {}
        for lnum = extmark_meta.topline, extmark_meta.botline do
            lines[#lines + 1] = M.lines[lnum] or ""
        end
        utils.set_text(bufnr, lines, extmark_meta.topline - 1, extmark_meta.botline)
    end
    api.nvim_buf_clear_namespace(bufnr, extmark_meta.ns, 0, -1)

    extmark_meta.topline = topline
    extmark_meta.botline = botline

    local visible_lines = {}
    local row_spans = {}
    for lnum = topline, botline do
        local line, spans = build_display_line(lnum)
        visible_lines[#visible_lines + 1] = line
        if spans and #spans > 0 then
            row_spans[#row_spans + 1] = { row = lnum - 1, spans = spans }
        end
    end
    utils.set_text(bufnr, visible_lines, topline - 1, botline)

    -- In custom mode extmarks only carry highlight ranges. The label text itself
    -- stays in the buffer so scrolling updates are just normal line writes.
    for _, row_data in ipairs(row_spans) do
        for _, span in ipairs(row_data.spans) do
            api.nvim_buf_set_extmark(
                bufnr,
                extmark_meta.ns,
                row_data.row,
                span.start_col,
                vim.tbl_extend("force", config.opts.ui.node_label.extmark_opts or {}, {
                    end_row = row_data.row,
                    end_col = span.end_col,
                    hl_group = span.hl_group,
                    strict = false,
                })
            )
        end
    end
end

return M
