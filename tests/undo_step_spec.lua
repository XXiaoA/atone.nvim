---@diagnostic disable: undefined-global, undefined-field
local atone = require("atone")
local core = require("atone.core")
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
        vim.o.undolevels = vim.o.undolevels -- force undo break in buf's context
    end)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 1" })
    api.nvim_buf_call(buf, function()
        vim.o.undolevels = vim.o.undolevels
    end)
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 2" })
    return buf
end

describe("undo / redo", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = false } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
    end)

    it("undo reverts one step in the attached buffer", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            assert.are.same({ "edit 2" }, api.nvim_buf_get_lines(buf, 0, -1, false))

            -- trigger undo via the buffer-local keymap on _auto_diff_buf
            local keymaps = api.nvim_buf_get_keymap(core._auto_diff_buf, "n")
            local fn_undo
            for _, km in ipairs(keymaps) do
                if km.lhs == "u" then
                    fn_undo = km.callback
                    break
                end
            end
            assert.is_not_nil(fn_undo, "u keymap should be set on auto_diff_buf")
            fn_undo()

            assert.are.same({ "edit 1" }, api.nvim_buf_get_lines(buf, 0, -1, false))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("redo re-applies a reverted step", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()

            local keymaps = api.nvim_buf_get_keymap(core._auto_diff_buf, "n")
            local fn_undo, fn_redo
            for _, km in ipairs(keymaps) do
                if km.lhs == "u" then
                    fn_undo = km.callback
                end
                if km.lhs == "<C-r>" or km.lhs == "<C-R>" then
                    fn_redo = km.callback
                end
            end
            assert.is_not_nil(fn_redo, "<C-r> keymap should be set on auto_diff_buf")

            fn_undo()
            assert.are.same({ "edit 1" }, api.nvim_buf_get_lines(buf, 0, -1, false))

            fn_redo()
            assert.are.same({ "edit 2" }, api.nvim_buf_get_lines(buf, 0, -1, false))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("default keymaps are u and <C-r>", function()
        assert.are.equal("u", config.opts.keymaps.auto_diff.undo)
        assert.are.equal("<C-r>", config.opts.keymaps.auto_diff.redo)
    end)

    it("keeps fixed-width diff float height stable across refresh", function()
        local prev_lines = vim.o.lines
        local prev_columns = vim.o.columns
        local buf = make_buf_with_history()
        local ok, err = pcall(function()
            vim.o.lines = 41
            vim.o.columns = 120
            atone.setup({ diff_cur_node = { enabled = true, width = 40, split_percent = 0.3 } })

            api.nvim_buf_call(buf, function()
                core.open()

                local first_dummy_height = api.nvim_win_get_height(core._dummy_win)
                local first_diff_config = api.nvim_win_get_config(core._diff_win)

                core.refresh(true)

                local second_dummy_height = api.nvim_win_get_height(core._dummy_win)
                local second_diff_config = api.nvim_win_get_config(core._diff_win)

                assert.are.equal(first_dummy_height, second_dummy_height)
                assert.are.equal(first_dummy_height, first_diff_config.height)
                assert.are.equal(second_dummy_height, second_diff_config.height)
                assert.are.equal(first_dummy_height, first_diff_config.row)
                assert.are.equal(second_dummy_height, second_diff_config.row)
            end)
        end)

        vim.o.lines = prev_lines
        vim.o.columns = prev_columns
        api.nvim_buf_delete(buf, { force = true })
        if not ok then
            error(err)
        end
    end)
end)
