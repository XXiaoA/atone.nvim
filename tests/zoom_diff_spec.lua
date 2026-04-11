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

describe("zoom_diff", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = true } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
        if core._zoom_win and api.nvim_win_is_valid(core._zoom_win) then
            api.nvim_win_close(core._zoom_win, true)
            core._zoom_win = nil
        end
    end)

    it("opens a float showing _auto_diff_buf", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            assert.is_nil(core._zoom_win)

            -- trigger zoom_diff via keymap callback
            -- nvim_buf_get_keymap returns the lhs with <leader> expanded to its value
            local zoom_lhs = vim.keycode("<leader>uz")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fn_zoom
            for _, km in ipairs(keymaps) do
                if km.lhs == zoom_lhs then
                    fn_zoom = km.callback
                    break
                end
            end
            assert.is_not_nil(fn_zoom, "<leader>uz keymap should be set on tree buf")
            fn_zoom()

            assert.is_not_nil(core._zoom_win)
            assert.is_true(api.nvim_win_is_valid(core._zoom_win))
            assert.are.equal(core._auto_diff_buf, api.nvim_win_get_buf(core._zoom_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closes the zoom float on second call (toggle)", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            local zoom_lhs = vim.keycode("<leader>uz")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fn_zoom
            for _, km in ipairs(keymaps) do
                if km.lhs == zoom_lhs then
                    fn_zoom = km.callback
                end
            end
            fn_zoom()
            local zoom_win = core._zoom_win
            assert.is_true(api.nvim_win_is_valid(zoom_win))

            fn_zoom() -- toggle off
            assert.is_false(api.nvim_win_is_valid(zoom_win))
            assert.is_nil(core._zoom_win)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closing the zoom float does not close the atone layout", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            local zoom_lhs = vim.keycode("<leader>uz")
            local keymaps = api.nvim_buf_get_keymap(core._tree_buf, "n")
            local fn_zoom
            for _, km in ipairs(keymaps) do
                if km.lhs == zoom_lhs then
                    fn_zoom = km.callback
                end
            end
            fn_zoom()
            assert.is_true(core._show)

            api.nvim_win_close(core._zoom_win, true) -- close float directly
            assert.is_true(core._show, "atone layout should still be open")
            assert.is_true(api.nvim_win_is_valid(core._diff_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("default zoom size config is 0.8 x 0.8", function()
        assert.are.equal(0.8, config.opts.zoom.width)
        assert.are.equal(0.8, config.opts.zoom.height)
    end)
end)
