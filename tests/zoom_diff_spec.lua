---@diagnostic disable: undefined-global, undefined-field
local atone = require("atone")
local core = require("atone.core")
local config = require("atone.config")
local api = vim.api

local function make_buf()
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = ""
    vim.bo[buf].modifiable = true
    vim.bo[buf].swapfile = false
    api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
    return buf
end

describe("float_diff", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = true } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
        if core._float_diff_win and api.nvim_win_is_valid(core._float_diff_win) then
            api.nvim_win_close(core._float_diff_win, true)
            core._float_diff_win = nil
        end
    end)

    it("opens a float showing _auto_diff_buf", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            assert.is_nil(core._float_diff_win)

            -- trigger float_diff via keymap callback
            -- nvim_buf_get_keymap returns the lhs with <leader> expanded to its value
            local diff_float_lhs = vim.keycode("gd")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fd_diff_float
            for _, km in ipairs(keymaps) do
                if km.lhs == diff_float_lhs then
                    fd_diff_float = km.callback
                    break
                end
            end
            assert.is_not_nil(fd_diff_float, "gd keymap should be set on tree buf")
            fd_diff_float()

            assert.is_not_nil(core._float_diff_win)
            assert.is_true(api.nvim_win_is_valid(core._float_diff_win))
            assert.are.equal(core._auto_diff_buf, api.nvim_win_get_buf(core._float_diff_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closes the diff float on second call (toggle)", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            local diff_float_lhs = vim.keycode("gd")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fd_diff_float
            for _, km in ipairs(keymaps) do
                if km.lhs == diff_float_lhs then
                    fd_diff_float = km.callback
                end
            end
            fd_diff_float()
            local diff_float_win = core._float_diff_win
            assert.is_true(api.nvim_win_is_valid(diff_float_win))

            fd_diff_float() -- toggle off
            assert.is_false(api.nvim_win_is_valid(diff_float_win))
            assert.is_nil(core._float_diff_win)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closing the diff float does not close the atone layout", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            local diff_float_lhs = vim.keycode("gd")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fd_diff_float
            for _, km in ipairs(keymaps) do
                if km.lhs == diff_float_lhs then
                    fd_diff_float = km.callback
                end
            end
            fd_diff_float()
            assert.is_true(core._show)

            api.nvim_win_close(core._float_diff_win, true) -- close float directly
            assert.is_true(core._show, "atone layout should still be open")
            assert.is_true(api.nvim_win_is_valid(core._diff_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("default diff float size config is 0.8 x 0.8", function()
        assert.are.equal(0.8, config.opts.diff_float.width)
        assert.are.equal(0.8, config.opts.diff_float.height)
    end)
end)
