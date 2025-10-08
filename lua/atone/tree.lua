local fn = vim.fn
local time_ago = require("atone.utils").time_ago
local Tree = {}

function Tree:new()
    local o = {
        root = { -- id == 0
            depth = 1,
            -- child is a descendant with the same depth as the node.
            child = nil,
            children = {},
            parent = 0,
        },
        nodes = {}, -- map { id: node }
        lines = {},
        total = 0,
        max_depth = 1,
        cur_id = 0,
    }

    self.__index = self
    setmetatable(o, self)
    return o
end

-- get the character at column `col` (1-based index)
local function get_char(line, col)
    return fn.strcharpart(line, col - 1, 1)
end

local function set_char_at(str, pos, ch)
    local len = fn.strchars(str)
    if pos > len then
        return str .. string.rep(" ", pos - len - 1) .. ch
    else
        return fn.strcharpart(str, 0, pos - 1) .. ch .. fn.strcharpart(str, pos)
    end
end

function Tree:node_at(id)
    return id == 0 and self.root or self.nodes[id]
end

function Tree:change_branch_depth(node_id, new_depth_baseline)
    local depth_difference = new_depth_baseline - self:node_at(node_id).depth
    local queue = { node_id }
    local head = 1
    while head <= #queue do
        local current_node = self:node_at(queue[head])
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

function Tree:convert(buf)
    local undotree = vim.fn.undotree(buf)
    -- clear the self.nodes!!!!
    self.nodes = {}
    local function flatten(rawtree, parent)
        for _, raw_node in ipairs(rawtree) do
            self.nodes[raw_node.seq] = {
                time = raw_node.time,
                parent = parent, -- 0 means the root node
                children = {},
            }
            if raw_node.alt then
                flatten(raw_node.alt, parent)
            end
            parent = raw_node.seq
        end
    end
    flatten(undotree.entries, 0)

    self.cur_id = undotree.seq_cur
    self.total = undotree.seq_last

    -- set the depth: the depth of each branch depth = the depth of its root node's parent node plus 1
    local visited = {}
    -- determine the main branch with a depth of 1
    do
        local id = self.total
        repeat
            local node = self:node_at(id)
            node.depth = 1
            visited[id] = true
            id = node.parent
        until id == 0
    end
    -- fill in depths for other branches
    for id = self.total - 1, 1, -1 do
        if not visited[id] then
            local path = {}
            local sub_id = id
            local sub_node = self:node_at(sub_id)
            repeat
                table.insert(path, sub_id)
                visited[sub_id] = true
                sub_id = sub_node.parent
                sub_node = self:node_at(sub_id)
            until sub_node.depth
            local base_depth = self:node_at(sub_id).depth
            for _, i in ipairs(path) do
                self:node_at(i).depth = base_depth + 1
            end
        end
    end

    for id = self.total, 1, -1 do
        local node = self:node_at(id)
        local parent_node = self:node_at(node.parent)
        table.insert(parent_node.children, id)
        if node.depth == parent_node.depth then
            parent_node.child = id
        end
    end

    for id = self.total, 2, -1 do
        local node = self:node_at(id)
        if node.depth ~= 1 and id ~= node.parent + 1 and not node.fork then
            for sub_id = id - 1, node.parent + 1, -1 do
                local sub_node = self:node_at(sub_id)
                local sub_node_parent = self:node_at(sub_node.parent)
                if
                    sub_node.depth == node.depth
                    and sub_node.depth ~= sub_node_parent.depth
                    and (sub_node.parent ~= node.parent or id > self:node_at(node.parent).child)
                then
                    if sub_id < sub_node_parent.child then
                        sub_node.fork = 1
                    end
                    self:change_branch_depth(sub_id, sub_node.depth + 1)
                end
            end
        end
    end

    for _, node in ipairs(self.nodes) do
        self.max_depth = math.max(self.max_depth, node.depth)
    end

    return self.nodes
end

function Tree:render()
    local buffer_lines = {}
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

    for id, node in ipairs(self.nodes) do
        local parent_depth = self:node_at(node.parent).depth
        local node_line = (self.total - id) * 2 + 1
        buffer_lines[node_line + 1] = "│" -- line after this node
        buffer_lines[node_line] = "│"
        buffer_lines[node_line] = set_char_at(buffer_lines[node_line], node.depth * 2 - 1, "●")
        buffer_lines[node_line] =
            set_char_at(buffer_lines[node_line], self.max_depth * 2 + 4, "[" .. id .. "] " .. time_ago(node.time))
        if not node.fork and node.depth ~= 1 then
            local line_is_drawing = node_line + 1
            while
                line_is_drawing < (self.total - node.parent) * 2 + 1
                and get_char(buffer_lines[line_is_drawing], node.depth * 2 - 1) ~= "●"
            do
                if get_char(buffer_lines[line_is_drawing], node.depth * 2 - 1) ~= "├" then
                    buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], node.depth * 2 - 1, "│")
                end
                line_is_drawing = line_is_drawing + 1
            end
            if node.depth ~= parent_depth then
                line_is_drawing = line_is_drawing - 1
                if get_char(buffer_lines[line_is_drawing], node.depth * 2) == "─" then
                    --  ●
                    --  │
                    --  │ ●
                    -- ─┴─╯
                    --  ^
                    buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], node.depth * 2 - 1, "┴")
                else
                    buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], node.depth * 2 - 1, "╯")
                end
                for pos = parent_depth * 2, node.depth * 2 - 2 do
                    if get_char(buffer_lines[line_is_drawing], pos) == " " then
                        buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], pos, "─")
                    elseif get_char(buffer_lines[line_is_drawing], pos) == "╯" then
                        buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], pos, "┴")
                    end
                end
                buffer_lines[line_is_drawing] = set_char_at(buffer_lines[line_is_drawing], parent_depth * 2 - 1, "├")
            end
        elseif node.fork then
            buffer_lines[node_line] = set_char_at(buffer_lines[node_line], parent_depth * 2 - 1, "├")
            for i = parent_depth * 2, node.depth * 2 - 2 do
                buffer_lines[node_line] = set_char_at(buffer_lines[node_line], i, "─")
            end
        end
    end
    buffer_lines[self.total * 2 + 1] = "●" .. string.rep(" ", self.max_depth * 2 + 2) .. "[0] Original"

    self.lines = buffer_lines
    return buffer_lines
end

return Tree
