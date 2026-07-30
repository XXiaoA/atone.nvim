local api, fn = vim.api, vim.fn
local config = require("atone.config")
local mark = require("atone.mark")
local tree = require("atone.tree")
local utils = require("atone.utils")

local M = {}

---@type table<string, { [1]: fun(), [2]: string }>
M.actions = {
    quit = {
        function()
            require("atone.core").close()
        end,
        "Close all atone windows",
    },
    quit_help = {
        function()
            pcall(api.nvim_win_close, require("atone.core")._float_win, true)
        end,
        "Close help window",
    },
    next_node = {
        function()
            local core = require("atone.core")
            core.pos_cursor_by_id(math.ceil(core.id_under_cursor()) - vim.v.count1)
        end,
        "Jump to next node (v:count supported)",
    }, -- support v:count
    pre_node = {
        function()
            local core = require("atone.core")
            core.pos_cursor_by_id(math.floor(core.id_under_cursor()) + vim.v.count1)
        end,
        "Jump to previous node (v:count supported)",
    }, -- support v:count
    jump_to_G = {
        function()
            require("atone.core").pos_cursor_by_id(tree.seq_2id(vim.v.count))
        end,
        "Jump to the node with the specified sequence number like G",
    },
    jump_to_gg = {
        function()
            local target_seq = vim.v.count == 0 and tree.last_seq or vim.v.count
            require("atone.core").pos_cursor_by_id(tree.seq_2id(target_seq))
        end,
        "Jump to the node with the specified sequence number like gg",
    },
    undo_to = {
        function()
            local core = require("atone.core")
            local seq = core.get_seq_under_cursor()
            if seq then
                api.nvim_buf_call(core.attach_buf, function()
                    vim.cmd("silent undo " .. seq)
                end)
                core.refresh()
            end
        end,
        "Undo to the node under cursor",
    },
    help = {
        function()
            require("atone.core").show_help()
        end,
        "Show help page",
    },
    set_mark = {
        function()
            local core = require("atone.core")
            local seq = core.get_seq_under_cursor()
            if not seq then
                return
            end
            local filepath = utils.buf_filepath(core.attach_buf)
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
                    core.refresh(true)
                end)
            end
            ask()
        end,
        "Set a mark on the node under cursor",
    },
    delete_mark = {
        function()
            local core = require("atone.core")
            local seq = core.get_seq_under_cursor()
            if not seq then
                return
            end
            local filepath = utils.buf_filepath(core.attach_buf)
            local seq_marks = mark.get_by_seq(filepath, seq)
            if #seq_marks == 0 then
                vim.notify("Atone: No marks on this node", vim.log.levels.INFO)
                return
            end
            if #seq_marks == 1 then
                mark.delete_mark(filepath, seq_marks[1].name)
                core.refresh(true)
            else
                local names = vim.tbl_map(function(m)
                    return m.name
                end, seq_marks)
                vim.ui.select(names, { prompt = "Delete mark: " }, function(_, idx)
                    if idx then
                        mark.delete_mark(filepath, seq_marks[idx].name)
                        core.refresh(true)
                    end
                end)
            end
        end,
        "Delete the mark on the node under cursor",
    },
    goto_mark = {
        function()
            local core = require("atone.core")
            local filepath = utils.buf_filepath(core.attach_buf)
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
                        core.pos_cursor_by_id(id)
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
            local core = require("atone.core")
            local filepath = utils.buf_filepath(core.attach_buf)
            local marks = mark.get_marks(filepath)
            if vim.tbl_isempty(marks) then
                vim.notify("Atone: No marks in this buffer", vim.log.levels.INFO)
                return
            end
            mark.delete_all_marks(filepath)
            core.refresh(true)
        end,
        "Delete all marks in current buffer",
    },
    mark_picker = {
        function()
            local core = require("atone.core")
            mark.pick(core.attach_buf, function(m)
                if m then
                    local id = tree.seq_2id(m.seq)
                    if id then
                        core.pos_cursor_by_id(id)
                    end
                end
            end)
        end,
        "Open mark picker",
    },
    set_sticky_ref = {
        function()
            local core = require("atone.core")
            if core._sticky_ref ~= nil then
                core._sticky_ref = nil
            else
                local seq = core.get_seq_under_cursor()
                if not seq then
                    return
                end
                core._sticky_ref = seq
            end
            core.refresh(true)
        end,
        "Set/clear sticky diff reference (diff always computed against this node)",
    },
    float_diff = {
        function()
            local core = require("atone.core")
            if utils.win_exists(core._centered_diff_win) then
                api.nvim_win_close(core._centered_diff_win, true)
                return
            end
            local seq = core.get_seq_under_cursor() or tree.cur_seq
            if not seq or not (core._centered_diff_buf and api.nvim_buf_is_valid(core._centered_diff_buf)) then
                return
            end
            core.update_diff_views(seq)
            local w = math.floor(vim.o.columns * config.opts.diff_float.width)
            local h = math.floor(vim.o.lines * config.opts.diff_float.height)
            core._centered_diff_win = utils.new_win("float", core._centered_diff_buf, {
                win_config = {
                    relative = "editor",
                    row = math.floor((vim.o.lines - h) / 2),
                    col = math.floor((vim.o.columns - w) / 2),
                    width = w,
                    height = h,
                    style = "minimal",
                    border = config.opts.ui.border,
                    zindex = 100,
                },
                autoclose = config.opts.diff_float.autoclose,
            })
            api.nvim_set_option_value("winhl", "Normal:NormalFloat", { win = core._centered_diff_win })
        end,
        "Toggle diff float: diff in a centred floating window",
    },
    undo = {
        function()
            local core = require("atone.core")
            api.nvim_buf_call(core.attach_buf, function()
                vim.cmd("silent undo")
            end)
            core.refresh()
        end,
        "Undo one step in the attached buffer",
    },
    redo = {
        function()
            local core = require("atone.core")
            api.nvim_buf_call(core.attach_buf, function()
                vim.cmd("silent redo")
            end)
            core.refresh()
        end,
        "Redo one step in the attached buffer",
    },
}

---@type table<string, { [1]: string|string[], [2]: string }>
M.used_mappings = {}

return M
