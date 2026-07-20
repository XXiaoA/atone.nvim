---@diagnostic disable: undefined-global, undefined-field
local atone = require("atone")
local core = require("atone.core")
local tree = require("atone.tree")
local diff = require("atone.diff")
local config = require("atone.config")
local api = vim.api

local function make_buf_with_history()
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = ""
    vim.bo[buf].modifiable = true
    vim.bo[buf].swapfile = false
    vim.bo[buf].undolevels = 64
    api.nvim_buf_set_lines(buf, 0, -1, false, { "original" })
    api.nvim_buf_call(buf, function()
        vim.o.undolevels = vim.o.undolevels
    end)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 1" })
    api.nvim_buf_call(buf, function()
        vim.o.undolevels = vim.o.undolevels
    end)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 2" })
    return buf
end

local function get_keymap_callback(buf, lhs)
    local keymaps = api.nvim_buf_get_keymap(buf, "n")
    local target = vim.keycode(lhs)
    for _, km in ipairs(keymaps) do
        if km.lhs == target then
            return km.callback
        end
    end
end

--- Convert a seq to the tree-buffer line number where that node lives.
local function seq_to_lnum(seq)
    local id = tree.seq_2id(seq)
    local compact = config.opts.ui.compact
    return compact and tree.total - id + 1 or (tree.total - id) * 2 + 1
end

--- Sorted real seqs (excluding root seq 0).
local function real_seqs()
    local seqs = vim.tbl_keys(tree.nodes)
    table.sort(seqs)
    return vim.tbl_filter(function(s)
        return s > 0
    end, seqs)
end

describe("sticky ref", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = true } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
        core._sticky_ref = nil
    end)

    it("= sets sticky ref to the seq under cursor", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            assert.is_nil(core._sticky_ref)

            local set_sticky = get_keymap_callback(core._tree_buf, "=")
            assert.is_not_nil(set_sticky, "= keymap should be set on tree buf")
            set_sticky()

            assert.are.equal(tree.cur_seq, core._sticky_ref)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("= toggles sticky ref off on second press", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            local set_sticky = get_keymap_callback(core._tree_buf, "=")

            set_sticky()
            assert.is_not_nil(core._sticky_ref)

            set_sticky()
            assert.is_nil(core._sticky_ref)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("diff uses sticky ref as base instead of parent", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            local seqs = real_seqs()
            local ref_seq = seqs[1]
            local target = seqs[#seqs]

            core._sticky_ref = ref_seq
            api.nvim_win_set_cursor(core._tree_win, { seq_to_lnum(target), 0 })
            core.refresh(true)

            local expected = diff.get_diff(diff.get_context_by_seq(buf, ref_seq), diff.get_context_by_seq(buf, target))
            local actual = api.nvim_buf_get_lines(core._auto_diff_buf, 1, -1, false)
            assert.are.same(expected, actual)

            -- Confirm it differs from the parent-based diff
            local parent_seq = tree.nodes[target].parent
            local parent_diff = diff.get_diff(diff.get_context_by_seq(buf, parent_seq), diff.get_context_by_seq(buf, target))
            assert.are_not.same(parent_diff, actual)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("header shows [old] → [new] with seq numbers", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            local seqs = real_seqs()
            local ref_seq = seqs[1]
            local target = seqs[#seqs]

            core._sticky_ref = ref_seq
            api.nvim_win_set_cursor(core._tree_win, { seq_to_lnum(target), 0 })
            core.refresh(true)

            local expected_header = string.format("[%d] → [%d]", ref_seq, target)
            local actual_header = api.nvim_buf_get_lines(core._auto_diff_buf, 0, 1, false)[1]
            assert.are.equal(expected_header, actual_header)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("header disappears when sticky ref is cleared", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            core._sticky_ref = tree.cur_seq
            core.refresh(true)
            local header_line = api.nvim_buf_get_lines(core._auto_diff_buf, 0, 1, false)[1]
            assert.is_truthy(header_line:match("→"))

            core._sticky_ref = nil
            core.refresh(true)
            local first_line = api.nvim_buf_get_lines(core._auto_diff_buf, 0, 1, false)[1]
            assert.is_nil(first_line:match("→"))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("stale sticky ref is cleared when its seq disappears from the tree", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            core._sticky_ref = 9999
            core.refresh(true)
            assert.is_nil(core._sticky_ref)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)
end)
