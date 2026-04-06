local api, fn = vim.api, vim.fn
local config = require("atone.config")
local utils = require("atone.utils")
local get_diff_by_seq = require("atone.diff").get_diff_by_seq
local get_diff_by_seq_cached = utils.cache(get_diff_by_seq)

local extmark_meta = {
    col = nil,
    ns = api.nvim_create_namespace("atone_tree"),
    ---@type table<integer, [string, string][]>
    items = {},
}

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

---@class AtoneNode
---@field seq integer
---@field time integer?
---@field depth integer
---@field parent integer?
---@field children integer[]
---@field child integer?
---@field bufnr integer
---@field fork boolean?
---@field label string|table|nil

---@class AtoneNode.Label.Ctx.Diff
---@field added integer
---@field removed integer

---@class AtoneNode.Label.Ctx
---@field seq integer
---@field is_current boolean
---@field time integer
---@field h_time string Time in a human-readable format
---@field diff AtoneNode.Label.Ctx.Diff Diff statistics

local M = {
    ---@type table<integer, AtoneNode>
    --- { seq: node } mapping
    nodes = {},
    lines = {},
    total = 1,
    last_seq = 0,
    cur_seq = 0,
}

---@param node AtoneNode
local function get_node_label(node)
    local h_time
    if node.seq > 0 and node.time ~= nil then
        h_time = utils.time_ago(node.time)
    else
        h_time = "Original"
    end

    local ctx = {
        seq = node.seq,
        is_current = node.seq == M.cur_seq,
        time = node.time,
        h_time = h_time,
        diff = function()
            local diff_patch = get_diff_by_seq_cached(node.bufnr, node.seq)

            ---@type AtoneNode.Label.Ctx.Diff
            local diff_stats = { added = 0, removed = 0 }
            vim.iter(diff_patch):each(function(line)
                if line:find("^+") ~= nil then
                    diff_stats.added = diff_stats.added + 1
                elseif line:find("^-") ~= nil then
                    diff_stats.removed = diff_stats.removed + 1
                end
            end)
            return diff_stats
        end,
    }

    local label = config.opts.ui.node_label.formatter(setmetatable({}, {
        __index = function(t, k)
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
    else
        return vim.iter(label)
            :map(function(item)
                if type(item) == "table" then
                    return { tostring(item[1]), item[2] or "Normal" }
                else
                    return { tostring(item), "Normal" }
                end
            end)
            :totable()
    end
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
    local undotree = fn.undotree(buf)

    -- initiate
    M.nodes = {}
    M.nodes[0] = {
        seq = 0,
        depth = 1,
        -- child is a descendant with the same depth as the node.
        child = nil,
        children = {},
        bufnr = buf,
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
                bufnr = buf,
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
function M.render(marks_labels)
    marks_labels = marks_labels or {}
    M.lines = {}
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
    if compact then
        M.lines[total] = "●"
    else
        M.lines[2 * total - 1] = "●"
    end
    id = 2
    while id <= total do
        local seq = seqs[id]
        local node = M.nodes[seq]
        local depth = node.depth
        local parent_depth = M.nodes[node.parent].depth
        local node_lnum = compact and total - id + 1 or (total - id) * 2 + 1
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
    local core = require("atone.core")

    local wininfo = fn.getwininfo(core._tree_win)[1]
    local topline = wininfo.topline or 1
    local botline = wininfo.topline + wininfo.height + 2

    extmark_meta.col = label_col
    extmark_meta.items = {}
    do
        for i = 1, total do
            local lnum = compact and total - i + 1 or (total - i) * 2 + 1

            if lnum >= topline and lnum <= botline then
                local seq = M.id_2seq(i)
                local node = M.nodes[seq]

                node.label = node.label or get_node_label(node)
                local label = node.label

                if type(label) == "string" then
                    M.lines[lnum] = set_char_at(M.lines[lnum], label_col, tostring(label))
                elseif type(label) == "table" then
                    extmark_meta.items[lnum - 1] = label
                end
            end

            -- local target_index = max_depth * 2 + 4
            -- local label = marks_labels[seq]
            -- local label_suffix = label and label or ""
            -- local content = string.format("[%s] %s %s", seq, time, label_suffix)
            -- M.lines[lnum] = set_char_at(M.lines[lnum], target_index, content)
        end
    end

    return M.lines
end

api.nvim_set_decoration_provider(extmark_meta.ns, {
    on_win = function(_, winid, bufnr, toprow, botrow)
        local core = require("atone.core")
        if core._tree_buf ~= bufnr or core._tree_buf == nil then
            return
        end
        if vim.tbl_isempty(extmark_meta.items) then
            return
        end

        api.nvim_buf_clear_namespace(core._tree_buf, extmark_meta.ns, 0, -1)

        for lnum = math.max(toprow - 1, 0), botrow do
            local label = extmark_meta.items[lnum]
            if label then
                api.nvim_buf_set_extmark(
                    bufnr,
                    extmark_meta.ns,
                    lnum,
                    extmark_meta.col,
                    vim.tbl_deep_extend(
                        "force",
                        config.opts.ui.node_label.extmark_opts or {},
                        { virt_text = label, virt_text_win_col = extmark_meta.col }
                    )
                )
            end
        end
    end,
})

return M
