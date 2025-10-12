local api, fn = vim.api, vim.fn
local ns = api.nvim_create_namespace("atone.tree")
local diff = require("atone.diff")

local config = require("atone.config")
local time_ago = require("atone.utils").time_ago

--- get the character at column `col` (1-based index)
---@param line string
---@param col integer
---@return string
local function get_char(line, col)
    return fn.strcharpart(line, col - 1, 1)
end

--- change the char of str in pos index.
---@param str string
---@param pos integer
---@param ch string
local function set_char_at(str, pos, ch)
    local len = fn.strchars(str)
    if pos > len then
        return str .. string.rep(" ", pos - len - 1) .. ch
    else
        return fn.strcharpart(str, 0, pos - 1) .. ch .. fn.strcharpart(str, pos)
    end
end

---@param node Atone.Tree.Node
---@param diff_patch string[]
---@return string|table[]
local function get_label(node, diff_patch)
    ---@type Atone.Tree.Node.Label.Ctx.Diff
    local diff_stats = { added = 0, removed = 0 }
    vim.iter(diff_patch):each(function(line)
        if line:find("^-") ~= nil then
            diff_stats.added = diff_stats.added + 1
        elseif line:find("^+") ~= nil then
            diff_stats.removed = diff_stats.removed + 1
        end
    end)

    local label = config.opts.node_label_formatter({
        seq = node.seq,
        time = node.time or 0,
        h_time = time_ago(node.time or 0),
        diff = diff_stats,
    })
    if type(label) == "string" then
        return label
    else
        return vim.iter(label)
            :map(function(item)
                if type(item) == "string" then
                    return { item, "Normal" }
                else
                    return item
                end
            end)
            :totable()
    end
end

local M = {
    ---@type Atone.Tree.Node
    root = {
        seq = 0,
        depth = 1,
        -- child is a descendant with the same depth as the node.
        child = nil,
        children = {},
        parent = 0,
    },
    ---@type table<integer, Atone.Tree.Node>
    nodes = {}, -- map { id: node }
    lines = {},
    last_seq = 0,
    max_depth = 1,
    cur_seq = 0,
    earliest_seq = 1, -- this value is not 1 when vim.o.undolevels < last_seq
}

---@class Atone.Tree.Node
---@field seq integer
---@field time? integer
---@field depth? integer
---@field child? integer
---@field children Atone.Tree.Node[]
---@field parent integer
---@field bufnr? integer The buffer number of the original buffer
---@field fork? boolean

---@class Atone.Tree.Node.Label.Ctx.Diff
---@field added integer
---@field removed integer

---@class Atone.Tree.Node.Label.Ctx
---@field seq integer
---@field time integer
---@field h_time string Time in a human-readable format
---@field diff Atone.Tree.Node.Label.Ctx.Diff Diff statistics

---@return Atone.Tree.Node
function M.node_at(seq)
    return seq < M.earliest_seq and M.root or M.nodes[seq]
end

function M.change_branch_depth(node_seq, new_depth_baseline)
    local depth_difference = new_depth_baseline - M.node_at(node_seq).depth
    local queue = { node_seq }
    local head = 1
    while head <= #queue do
        local current_node = M.node_at(queue[head])
        head = head + 1
        current_node.depth = current_node.depth + depth_difference
        local children_ids = current_node.children
        if not vim.tbl_isempty(children_ids) then
            for _, child_id in ipairs(children_ids) do
                table.insert(queue, child_id)
            end
        end
    end
end

function M.convert(buf)
    -- clear the tree.nodes!!!!
    M.nodes = {}
    M.root.bufnr = buf
    M.root.time = os.time()
    local undotree = fn.undotree(buf)
    local function flatten(rawtree, parent)
        for _, raw_node in ipairs(rawtree) do
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
        end
    end
    flatten(undotree.entries, 0)

    M.cur_seq = undotree.seq_cur
    M.last_seq = undotree.seq_last

    local ul = api.nvim_get_option_value("undolevels", { buf = buf })
    if ul == -123456 then -- The local value is set to -123456 when the global value is to be used.
        ul = api.nvim_get_option_value("undolevels", { scope = "global" })
    end
    if M.last_seq > ul + 1 then
        M.earliest_seq = M.last_seq - ul
        while not M.nodes[M.earliest_seq] do
            M.earliest_seq = M.earliest_seq + 1
        end
    end

    -- set the depth: the depth of each branch depth = the depth of its root node's parent node plus 1
    local visited = {}
    -- determine the main branch with a depth of 1
    do
        local seq = undotree.seq_last
        repeat
            local node = M.node_at(seq)
            node.depth = 1
            visited[seq] = true
            seq = node.parent
        until seq == 0
    end
    -- fill in depths for other branches
    for seq = M.last_seq - 1, M.earliest_seq, -1 do
        if not visited[seq] then
            local path = {}
            local sub_seq = seq
            local sub_node = M.node_at(sub_seq)
            repeat
                table.insert(path, sub_seq)
                visited[sub_seq] = true
                sub_seq = sub_node.parent
                sub_node = M.node_at(sub_seq)
            until sub_node.depth
            local base_depth = M.node_at(sub_seq).depth
            for _, i in ipairs(path) do
                M.node_at(i).depth = base_depth + 1
            end
        end
    end

    for seq = M.last_seq, M.earliest_seq, -1 do
        local node = M.node_at(seq)
        local parent_node = M.node_at(node.parent)
        table.insert(parent_node.children, seq)
        if node.depth == parent_node.depth then
            parent_node.child = seq
        end
    end

    -- adjust the depth
    for seq = M.last_seq, M.earliest_seq + 1, -1 do
        local node = M.node_at(seq)
        if node.depth ~= 1 and seq ~= node.parent + 1 and not node.fork then
            for sub_seq = seq - 1, node.parent + 1, -1 do
                local sub_node = M.node_at(sub_seq)
                local sub_node_parent = M.node_at(sub_node.parent)
                if
                    sub_node.depth == node.depth
                    and sub_node.depth ~= sub_node_parent.depth
                    and (sub_node.parent ~= node.parent or seq > M.node_at(node.parent).child)
                then
                    if sub_seq < sub_node_parent.child then
                        sub_node.fork = true
                    end
                    M.change_branch_depth(sub_seq, sub_node.depth + 1)
                end
            end
        end
    end

    for seq = M.earliest_seq, M.last_seq do
        local node = M.node_at(seq)
        M.max_depth = math.max(M.max_depth, node.depth)
    end

    return M.nodes
end

function M.render()
    M.lines = {}
    -- we should reverse the table: put the node with greater id in the smaller index
    -- @    [4] 1
    -- |        2
    -- | o  [3] 3
    -- | |      4                                    1    2     3      4     5       6      7     8    9
    -- | o  [2] 5                             <=> { "o", "|", "| o", "| |", "| o", "| |", "o |", "|/", "o"}
    -- | |      6
    -- o |  [1] 7  <- a node
    -- |/       8  <- line after this node
    -- o    [0] 9

    local core = require("atone.core")
    local tree_buf = assert(core.get_tree_buf())
    for seq = M.earliest_seq, M.last_seq do
        local node = M.nodes[seq]
        local parent_depth = M.node_at(node.parent).depth
        local node_line = (M.last_seq - seq) * 2 + 1
        M.lines[node_line + 1] = "│" -- line after this node
        M.lines[node_line] = "│"
        M.lines[node_line] = set_char_at(M.lines[node_line], node.depth * 2 - 1, "●")

        local diff_patch =
            diff.get_diff(diff.get_context(node.bufnr, M.node_at(node.parent).seq), diff.get_context(node.bufnr, node.seq))
        local label = get_label(node, diff_patch)

        local col = M.max_depth * 2 + 4
        if type(label) == "string" then
            M.lines[node_line] = set_char_at(M.lines[node_line], col, label)
        else
            vim.schedule_wrap(api.nvim_buf_set_extmark)(
                tree_buf,
                ns,
                node_line - 1,
                0,
                { virt_text = label, strict = false, virt_text_pos = "eol_right_align", priority = 10000 }
            )
        end

        if not node.fork and node.depth ~= 1 then
            local line_is_drawing = node_line + 1
            while
                line_is_drawing < (M.last_seq - node.parent) * 2 + 1
                and line_is_drawing < (M.last_seq - M.earliest_seq + 1) * 2 + 1
                -- ●
                -- │
                -- │ ●
                -- ├─╯
                -- │ ●
                -- ├─╯
                -- ●
                and get_char(M.lines[line_is_drawing], node.depth * 2 - 1) ~= "●"
            do
                if get_char(M.lines[line_is_drawing], node.depth * 2 - 1) ~= "├" then
                    M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], node.depth * 2 - 1, "│")
                end
                line_is_drawing = line_is_drawing + 1
            end
            if node.depth ~= parent_depth then
                line_is_drawing = line_is_drawing - 1
                if get_char(M.lines[line_is_drawing], node.depth * 2) == "─" then
                    --  ●
                    --  │
                    --  │ ●
                    -- ─┴─╯
                    --  ^
                    M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], node.depth * 2 - 1, "┴")
                else
                    M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], node.depth * 2 - 1, "╯")
                end
                for pos = parent_depth * 2, node.depth * 2 - 2 do
                    if get_char(M.lines[line_is_drawing], pos) == " " then
                        M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], pos, "─")
                    elseif get_char(M.lines[line_is_drawing], pos) == "╯" then
                        M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], pos, "┴")
                    end
                end
                M.lines[line_is_drawing] = set_char_at(M.lines[line_is_drawing], parent_depth * 2 - 1, "├")
            end
        elseif node.fork then
            M.lines[node_line] = set_char_at(M.lines[node_line], parent_depth * 2 - 1, "├")
            for i = parent_depth * 2, node.depth * 2 - 2 do
                M.lines[node_line] = set_char_at(M.lines[node_line], i, "─")
            end
        end
    end

    local root_label = get_label(M.root, {})

    local root_line_nr = (M.last_seq - M.earliest_seq + 1) * 2 + 1
    M.lines[root_line_nr] = "●" .. string.rep(" ", M.max_depth * 2 + 2)
    if type(root_label) == "string" then
        M.lines[root_line_nr] = M.lines[(M.last_seq - M.earliest_seq + 1) * 2 + 1] .. root_label
    else
        vim.schedule_wrap(api.nvim_buf_set_extmark)(
            tree_buf,
            ns,
            root_line_nr - 1,
            0,
            { virt_text = root_label, strict = false, virt_text_pos = "eol_right_align", priority = 10000 }
        )
    end

    return M.lines
end

return M
