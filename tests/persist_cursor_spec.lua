---@diagnostic disable: undefined-global, undefined-field
local atone = require("atone")
local core = require("atone.core")
local api = vim.api

local function make_buf_with_history()
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_call(buf, function()
        vim.bo[buf].buftype = ""
        vim.bo[buf].modifiable = true
        vim.bo[buf].swapfile = false
        vim.bo[buf].undolevels = 64
        api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1" })
        vim.o.undolevels = vim.o.undolevels -- force undo break
        api.nvim_buf_set_lines(buf, -1, -1, false, { "line 2" })
        vim.o.undolevels = vim.o.undolevels
        api.nvim_buf_set_lines(buf, -1, -1, false, { "line 3" })
    end)
    return buf
end

describe("Persist cursor", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = false } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
    end)

    it("restores tree cursor position after close + re-open", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            -- Move cursor to the first (oldest) line of the tree
            local first_line = api.nvim_buf_line_count(core._tree_buf)
            api.nvim_win_set_cursor(core._tree_win, { first_line, 0 })
            local pos_before = api.nvim_win_get_cursor(core._tree_win)

            core.close()
            core.open()

            local pos_after = api.nvim_win_get_cursor(core._tree_win)
            assert.are.same(pos_before, pos_after)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("does not error when closing before any open", function()
        assert.has_no.errors(function()
            core.close()
        end)
    end)

    it("clears saved cursor after restoring (does not persist across two re-opens)", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            local first_line = api.nvim_buf_line_count(core._tree_buf)
            api.nvim_win_set_cursor(core._tree_win, { first_line, 0 })
            core.close()

            core.open()
            core.close()

            -- After the second close, _saved_tree_cursor is the position from that re-open,
            -- not the original. The key invariant: it was cleared once during the first re-open.
            assert.is_nil(core._saved_tree_cursor) -- cleared by close (set to new pos, then open clears it)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("does not restore cursor when persist_cursor = false", function()
        atone.setup({ diff_cur_node = { enabled = false }, persist_cursor = false })
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            local first_line = api.nvim_buf_line_count(core._tree_buf)
            api.nvim_win_set_cursor(core._tree_win, { first_line, 0 })
            core.close()

            core.open()
            -- cursor should be at the current undo node (top of tree), not the saved position
            assert.is_nil(core._saved_tree_cursor)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)
end)
