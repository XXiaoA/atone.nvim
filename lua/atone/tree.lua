local api, fn = vim.api, vim.fn
local ns = api.nvim_create_namespace("atone.tree")
local diff = require("atone.diff")

local config = require("atone.config")
local time_ago = require("atone.utils").time_ago

--- accept a string and return the start and end byte indices (1-based, inclusive)
--- for each of the characters.
---@param str string
---@return [integer, integer][]
local function break_down_utf(str)
    local idx = 1
    local res = {}

    while idx <= str:len() do
        local _start = idx + vim.str_utf_start(str, idx)
        local _end = idx + vim.str_utf_end(str, idx)
        res[#res + 1] = { _start, _end }
        idx = _end + 1
    end

    return res
end

--- get the character at column `col` (1-based index)
---@param line string
---@param col integer
---@return string
local function get_char(line, col)
    local range = break_down_utf(line)[col]
    if range then
        return line:sub(unpack(range))
    else
        return " "
    end
end

--- change the char of str in pos index.
---@param str string
---@param pos integer
---@param ch string
---@return string
local function set_char_at(str, pos, ch)
    local char_ranges = break_down_utf(str)
    if #char_ranges < pos then
        return str .. string.rep(" ", pos - #char_ranges - 1) .. ch
    else
        local partial = str:sub(pos == 1 and char_ranges[2][1] or 1, char_ranges[math.max(1, pos - 1)][2]) .. ch
        if #char_ranges > pos then
            partial = partial .. str:sub(char_ranges[pos + 1][1])
        end
        return partial
    end
end

---@class AtoneNode.Label.Ctx.Diff
---@field added integer
---@field removed integer

---@class AtoneNode.Label.Ctx
---@field seq integer
---@field time integer
---@field h_time string Time in a human-readable format
---@field diff AtoneNode.Label.Ctx.Diff Diff statistics

---@param node AtoneNode
---@return {[1]: string, [2]: string}[]
local function get_label(node)
    if node.diff_stats_from_parent == nil then
        -- cache the diff stats
        local diff_patch = diff.get_diff(
            diff.get_context_by_seq(node.bufnr, node.seq),
            diff.get_context_by_seq(node.bufnr, node.parent or 0)
        )
        ---@type AtoneNode.Label.Ctx.Diff
        local diff_stats = { added = 0, removed = 0 }
        vim.iter(diff_patch):each(function(line)
            if line:find("^-") ~= nil then
                diff_stats.added = diff_stats.added + 1
            elseif line:find("^+") ~= nil then
                diff_stats.removed = diff_stats.removed + 1
            end
        end)
        node.diff_stats_from_parent = diff_stats
    end

    local h_time
    if node.seq > 0 and node.time ~= nil then
        h_time = time_ago(node.time)
    else
        h_time = "Original"
    end
    local label = config.opts.node_label.formatter({
        seq = node.seq,
        time = node.time or 0,
        h_time = h_time,
        diff = node.diff_stats_from_parent,
    })
    if type(label) == "string" then
        return { { label, "Normal" } }
    else
        return vim.iter(label)
            :map(function(item)
                if type(item) == "string" then
                    return { item, "Normal" }
                else
                    return { tostring(item[1]), item[2] or "Normal" }
                end
            end)
            :totable()
    end
end

---@class AtoneNode
---@field seq integer
---@field time? integer
---@field depth? integer
---@field parent? integer
---@field children integer[]
---@field child? integer
---@field fork boolean?
---@field bufnr? integer
---@field diff_stats_from_parent? AtoneNode.Label.Ctx.Diff

local M = {
    --- { seq: node }
    ---@type table<integer, AtoneNode>
    nodes = {},
    lines = {},
    total = 1,
    last_seq = 0,
    cur_seq = 0,
    --- {buf: {seq: extmark_id} }
    ---@type table<integer, table<integer, integer >>
    extmark_ids = {},
}

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
    M.extmark_ids[buf] = M.extmark_ids[buf] or {}
    if M.nodes[0] and M.nodes[0].bufnr ~= buf then
        local prev_buf = M.nodes[0].bufnr
        local tree_buf = require("atone.core").get_tree_buf()
        if tree_buf then
            vim.iter(M.extmark_ids[prev_buf]):each(vim.schedule_wrap(function(k, v)
                api.nvim_buf_del_extmark(tree_buf, ns, v)
            end))
        end
    end

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

    if undotree.entries[1] == nil then
        return
    end

    local earliest_seq = undotree.entries[1].seq
    local function flatten(rawtree, parent)
        for _, raw_node in ipairs(rawtree) do
            M.nodes[raw_node.seq] = vim.tbl_deep_extend("force", M.nodes[raw_node.seq] or {}, {
                seq = raw_node.seq,
                time = raw_node.time,
                parent = parent, -- 0 means the root node
                children = {},
                bufnr = buf,
            })

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
--      seq  id  index
-- @    [4]   5    1
-- |               2
-- | o  [3]   4    3
-- | |             4
-- | o  [2]   3    5
-- | |             6
-- o |  [1]   2    7  <- a node
-- |/              8  <- line after this node
-- o    [0]   1    9
function M.render()
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

    M.lines[2 * total - 1] = "●"
    id = 2
    while id <= total do
        local seq = seqs[id]
        local node = M.nodes[seq]
        local depth = node.depth
        local parent_depth = M.nodes[node.parent].depth
        local node_lnum = (total - id) * 2 + 1
        if depth == 1 then
            M.lines[node_lnum] = "●"
        else
            M.lines[node_lnum] = "│" .. (" "):rep(node.depth * 2 - 3) .. "●"
        end
        M.lines[node_lnum + 1] = "│" -- line after this node
        if not node.fork and depth ~= 1 then
            local lnum_is_drawing = node_lnum + 1
            while
                lnum_is_drawing < (total - M.seq_2id(node.parent)) * 2 + 1 -- index of parent node
                and get_char(M.lines[lnum_is_drawing], depth * 2 - 1) ~= "●"
            do
                if get_char(M.lines[lnum_is_drawing], depth * 2 - 1) ~= "├" then
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "│")
                end
                lnum_is_drawing = lnum_is_drawing + 1
            end
            if depth ~= parent_depth then
                lnum_is_drawing = lnum_is_drawing - 1
                if get_char(M.lines[lnum_is_drawing], depth * 2) == "─" then
                    --  ●
                    --  │
                    --  │ ●
                    -- ─┴─╯
                    --  ^
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "┴")
                else
                    M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], depth * 2 - 1, "╯")
                end
                for pos = parent_depth * 2, depth * 2 - 2 do
                    if get_char(M.lines[lnum_is_drawing], pos) == " " then
                        M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], pos, "─")
                    elseif get_char(M.lines[lnum_is_drawing], pos) == "╯" then
                        M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], pos, "┴")
                    end
                end
                M.lines[lnum_is_drawing] = set_char_at(M.lines[lnum_is_drawing], parent_depth * 2 - 1, "├")
            end
        elseif node.fork then
            M.lines[node_lnum] = set_char_at(M.lines[node_lnum], parent_depth * 2 - 1, "├")
            for i = parent_depth * 2, depth * 2 - 2 do
                M.lines[node_lnum] = set_char_at(M.lines[node_lnum], i, "─")
            end
        end

        id = id + 1
    end

    local tree_buf = require("atone.core").get_tree_buf()
    assert(type(tree_buf) == "number", "Unable to find the tree buffer.")

    do
        for i = 1, total do
            local lnum = (total - i) * 2 + 1

            local seq = M.id_2seq(i)
            local node = M.nodes[seq]

            local label = get_label(node)

            if label ~= nil then
                vim.schedule(function()
                    M.extmark_ids[node.bufnr][node.seq] = api.nvim_buf_set_extmark(
                        tree_buf,
                        ns,
                        lnum - 1,
                        (M.lines[lnum]:len()) - 1,
                        vim.tbl_deep_extend("force", config.opts.node_label.extmark_opts or {}, {
                            virt_text = label,
                            id = M.extmark_ids[node.bufnr][node.seq],
                        })
                    )
                end)
            end
        end
    end

    return M.lines
end

return M
