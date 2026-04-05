local M = {}
local fn = vim.fn

--- In-memory storage: { [filepath] = { [name] = mark_entry } }
---@type table<string, table<string, table>>
M._marks = {}

--- Parse user input to extract optional slot and name.
--- Format: "N:name" for slot N, or just "name"
---@param input string
---@return string? name, integer? slot
function M.parse_input(input)
    local slot_str, name = input:match("^(%d+):(.+)$")
    if slot_str and name then
        if #slot_str > 1 then
            return nil, nil
        end
        return name, tonumber(slot_str)
    end

    local only_slot = input:match("^(%d+)$")
    if only_slot then
        if #only_slot > 1 then
            return nil, nil
        end
        return only_slot, tonumber(only_slot)
    end

    return input, nil
end

---@param filepath string
---@param seq integer
---@param name string
---@param slot integer?
function M.set_mark(filepath, seq, name, slot)
    if not M._marks[filepath] then
        M._marks[filepath] = {}
    end
    -- Clear any existing mark with the same slot
    if slot then
        for _, mark in pairs(M._marks[filepath]) do
            if mark.slot == slot then
                mark.slot = nil
            end
        end
    end
    M._marks[filepath][name] = {
        seq = seq,
        slot = slot,
        name = name,
        created_at = os.time(),
    }
    M.save()
end

---@param filepath string
---@param name string
function M.delete_mark(filepath, name)
    if M._marks[filepath] then
        M._marks[filepath][name] = nil
        if vim.tbl_isempty(M._marks[filepath]) then
            M._marks[filepath] = nil
        end
    end
    M.save()
end

---@param filepath string
function M.delete_all_marks(filepath)
    if M._marks[filepath] then
        M._marks[filepath] = nil
        M.save()
    end
end

---@param filepath string
---@return table<string, table>
function M.get_marks(filepath)
    return M._marks[filepath] or {}
end

---@param filepath string
---@param slot integer
---@return table?
function M.get_by_slot(filepath, slot)
    local marks = M.get_marks(filepath)
    for _, mark in pairs(marks) do
        if mark.slot == slot then
            return mark
        end
    end
    return nil
end

---@param filepath string
---@param seq integer
---@return table[]
function M.get_by_seq(filepath, seq)
    local marks = M.get_marks(filepath)
    local result = {}
    for _, mark in pairs(marks) do
        if mark.seq == seq then
            result[#result + 1] = mark
        end
    end
    return result
end

--- Remove marks that are no longer valid (seq not in valid_seqs)
---@param filepath string
---@param valid_nodes table<integer, table> -- map of seq to node
function M.prune(filepath, valid_nodes)
    local marks = M.get_marks(filepath)
    if vim.tbl_isempty(marks) then
        return
    end

    local removed_count = 0
    for name, mark in pairs(marks) do
        if not valid_nodes[mark.seq] then
            marks[name] = nil
            removed_count = removed_count + 1
        end
    end

    if removed_count > 0 then
        if vim.tbl_isempty(marks) then
            M._marks[filepath] = nil
        end
        M.save()
        vim.notify(
            string.format(
                "Atone: Removed %d invalid mark(s) for %s due to undo history changes",
                removed_count,
                fn.fnamemodify(filepath, ":t")
            ),
            vim.log.levels.INFO
        )
    end
end

--- Build display labels for tree rendering, keyed by seq
---@param filepath string
---@return table<integer, string>
function M.build_labels(filepath)
    local marks = M.get_marks(filepath)
    local seq_to_labels = {} -- table<seq, string[]>

    for _, mark in pairs(marks) do
        local label
        if mark.slot then
            if tostring(mark.slot) == mark.name then
                label = "{" .. mark.slot .. "}"
            else
                label = "{" .. mark.slot .. ":" .. mark.name .. "}"
            end
        else
            label = "{" .. mark.name .. "}"
        end

        if not seq_to_labels[mark.seq] then
            seq_to_labels[mark.seq] = {}
        end
        seq_to_labels[mark.seq][#seq_to_labels[mark.seq] + 1] = label
    end

    local labels = {}
    for seq, label_list in pairs(seq_to_labels) do
        table.sort(label_list)
        labels[seq] = table.concat(label_list, " ")
    end
    return labels
end

function M.save()
    local config = require("atone.config")
    if not config.opts.marks.persist then
        return
    end
    local path = config.opts.marks.persist_path
    local ok, json = pcall(vim.json.encode, M._marks)
    if not ok then
        vim.notify("Atone: Failed to encode marks", vim.log.levels.ERROR)
        return
    end
    local f = io.open(path, "w")
    if f then
        f:write(json)
        f:close()
    else
        vim.notify("Atone: Failed to write marks to " .. path, vim.log.levels.ERROR)
    end
end

function M.load()
    local config = require("atone.config")
    local path = config.opts.marks.persist_path
    local f = io.open(path, "r")
    if not f then
        return
    end
    local content = f:read("*a")
    f:close()
    if content and content ~= "" then
        local ok, data = pcall(vim.json.decode, content)
        if ok and type(data) == "table" then
            M._marks = data
        end
    end
end

--- Format a mark entry for display in pickers
---@param entry table
---@return string display, string ordinal
local function format_entry(entry)
    local time_ago = require("atone.utils").time_ago
    local slot_str = entry.slot and ("[" .. entry.slot .. "] ") or "    "
    local time_str = entry.created_at and time_ago(entry.created_at) or ""
    local name_str = entry.name
    if entry.slot and tostring(entry.slot) == entry.name then
        name_str = "Slot " .. entry.slot
    end
    local display = slot_str .. name_str .. "  (seq: " .. entry.seq .. ", " .. time_str .. ")"
    local ordinal = (entry.slot and tostring(entry.slot) or "") .. " " .. entry.name
    return display, ordinal
end

--- Open a picker (fzf-lua / telescope / vim.ui.select) to select a mark
---@param buf integer
---@param callback fun(mark: table?)
function M.pick(buf, callback)
    local utils = require("atone.utils")
    local filepath = utils.buf_filepath(buf)
    local marks = M.get_marks(filepath)
    if vim.tbl_isempty(marks) then
        vim.notify("Atone: No marks for this buffer", vim.log.levels.INFO)
        return
    end

    local diff = require("atone.diff")
    local marks_list = {}
    local display_entries = {}
    local entry_to_mark = {}
    for _, mark in pairs(marks) do
        marks_list[#marks_list + 1] = mark
        local display = format_entry(mark)
        display_entries[#display_entries + 1] = display
        entry_to_mark[display] = mark
    end

    local finders = {
        ["fzf-lua"] = function()
            local fzf_ok, fzf = pcall(require, "fzf-lua")
            if fzf_ok then
                local previewer = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
                function previewer:new(o, opts, fzf_win)
                    previewer.super.new(self, o, opts, fzf_win)
                    setmetatable(self, self)
                    return self
                end
                function previewer:parse_entry(entry_str)
                    local mark_entry = entry_to_mark[entry_str]
                    return {
                        path = "atone_diff_" .. (mark_entry and mark_entry.seq or 0),
                        content = mark_entry and diff.get_diff_by_seq(buf, mark_entry.seq) or {},
                        filetype = "diff",
                    }
                end
                function previewer:gen_winopts()
                    return { wrap = false, number = false }
                end

                fzf.fzf_exec(display_entries, {
                    prompt = "Atone Marks> ",
                    previewer = previewer,
                    actions = {
                        ["default"] = function(selected)
                            if selected and selected[1] then
                                callback(entry_to_mark[selected[1]])
                            end
                        end,
                    },
                })
                return true
            end
            return false
        end,
        ["telescope"] = function()
            local tel_ok = pcall(require, "telescope")
            if tel_ok then
                local pickers = require("telescope.pickers")
                local tel_finders = require("telescope.finders")
                local conf = require("telescope.config").values
                local actions = require("telescope.actions")
                local action_state = require("telescope.actions.state")
                local previewers = require("telescope.previewers")

                pickers
                    .new({}, {
                        prompt_title = "Atone Marks",
                        finder = tel_finders.new_table({
                            results = marks_list,
                            entry_maker = function(mark_entry)
                                local display, ordinal = format_entry(mark_entry)
                                return {
                                    value = mark_entry,
                                    display = display,
                                    ordinal = ordinal,
                                }
                            end,
                        }),
                        previewer = previewers.new_buffer_previewer({
                            define_preview = function(self, entry)
                                local diff_lines = diff.get_diff_by_seq(buf, entry.value.seq)
                                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, diff_lines)
                                vim.api.nvim_set_option_value("filetype", "diff", { buf = self.state.bufnr })
                            end,
                        }),
                        sorter = conf.generic_sorter({}),
                        attach_mappings = function(prompt_bufnr)
                            actions.select_default:replace(function()
                                actions.close(prompt_bufnr)
                                local selection = action_state.get_selected_entry()
                                if selection then
                                    callback(selection.value)
                                end
                            end)
                            return true
                        end,
                    })
                    :find()
                return true
            end
            return false
        end,
        ["builtin"] = function()
            vim.ui.select(display_entries, {
                prompt = "Select mark: ",
            }, function(_, idx)
                if idx then
                    callback(marks_list[idx])
                end
            end)
            return true
        end,
    }

    local config_finders = require("atone.config").opts.marks.finders
    for _, finder_name in ipairs(config_finders) do
        local handler = finders[finder_name]
        if handler then
            if handler() then
                return
            end
        end
    end
end

return M
