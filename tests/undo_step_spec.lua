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
    vim.o.undolevels = vim.o.undolevels -- force undo break
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 1" })
    vim.o.undolevels = vim.o.undolevels
    api.nvim_buf_set_lines(buf, 0, -1, false, { "edit 2" })
    return buf
end

describe("undo_step_back / undo_step_forward", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = false } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
    end)

    it("undo_step_back reverts one step in the attached buffer", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()
            assert.are.same({ "edit 2" }, api.nvim_buf_get_lines(buf, 0, -1, false))

            -- trigger undo_step_back via the buffer-local keymap on _auto_diff_buf
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

    it("undo_step_forward re-applies a reverted step", function()
        local buf = make_buf_with_history()
        api.nvim_buf_call(buf, function()
            core.open()

            local keymaps = api.nvim_buf_get_keymap(core._auto_diff_buf, "n")
            local fn_undo, fn_redo
            for _, km in ipairs(keymaps) do
                if km.lhs == "u" then fn_undo = km.callback end
                if km.lhs == "<C-r>" then fn_redo = km.callback end
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
        assert.are.equal("u", config.opts.keymaps.auto_diff.undo_step_back)
        assert.are.equal("<C-r>", config.opts.keymaps.auto_diff.undo_step_forward)
    end)
end)
