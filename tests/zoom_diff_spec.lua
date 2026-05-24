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

local function get_keymap_callback(buf, lhs)
    local keymaps = api.nvim_buf_get_keymap(buf, "n")
    local target = vim.keycode(lhs)
    for _, km in ipairs(keymaps) do
        if km.lhs == target then
            return km.callback
        end
    end
end

describe("float_diff", function()
    before_each(function()
        atone.setup({ diff_cur_node = { enabled = true } })
    end)

    after_each(function()
        if core._show then
            core.close()
        end
        if core._centered_diff_win and api.nvim_win_is_valid(core._centered_diff_win) then
            api.nvim_win_close(core._centered_diff_win, true)
        end
    end)

    it("opens a centred float with its own diff buffer", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            assert.is_not_nil(open_float, "gd keymap should be set on tree buf")
            open_float()

            assert.is_true(api.nvim_win_is_valid(core._centered_diff_win))
            assert.are.equal(core._centered_diff_buf, api.nvim_win_get_buf(core._centered_diff_win))
            assert.are_not.equal(core._auto_diff_buf, core._centered_diff_buf)
            assert.is_true(#api.nvim_buf_get_lines(core._centered_diff_buf, 0, -1, false) > 0)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("opens from the diff window and keeps float highlighting", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()
            api.nvim_set_current_win(core._diff_win)

            local open_float = get_keymap_callback(core._auto_diff_buf, "gd")
            assert.is_not_nil(open_float, "gd keymap should be set on diff buf")
            open_float()

            assert.are.equal("Normal:NormalFloat", api.nvim_get_option_value("winhl", { win = core._centered_diff_win }))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("toggles off on second gd", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()
            local diff_float_win = core._centered_diff_win
            assert.is_true(api.nvim_win_is_valid(diff_float_win))

            open_float()
            assert.is_false(api.nvim_win_is_valid(diff_float_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closing the centred float does not close the atone layout", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()

            api.nvim_win_close(core._centered_diff_win, true)

            assert.is_true(core._show)
            assert.is_true(api.nvim_win_is_valid(core._tree_win))
            assert.is_true(api.nvim_win_is_valid(core._diff_win))
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("closing the main diff window still closes the atone layout", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()
            api.nvim_win_close(core._diff_win, true)

            assert.is_false(core._show)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("autocloses the centred float by default", function()
        local buf = make_buf()
        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()
            local diff_float_win = core._centered_diff_win
            assert.is_true(api.nvim_win_is_valid(diff_float_win))

            api.nvim_set_current_win(core._tree_win)
            vim.wait(100, function()
                return not api.nvim_win_is_valid(diff_float_win)
            end)

            assert.is_false(api.nvim_win_is_valid(diff_float_win))
            assert.is_true(core._show)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("can open centred diff even when auto diff is disabled", function()
        local buf = make_buf()
        atone.setup({ diff_cur_node = { enabled = false } })

        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()

            assert.is_true(api.nvim_win_is_valid(core._centered_diff_win))
            assert.are.equal(core._centered_diff_buf, api.nvim_win_get_buf(core._centered_diff_win))
            assert.is_true(#api.nvim_buf_get_lines(core._centered_diff_buf, 0, -1, false) > 0)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("keeps the centred float open when autoclose is disabled", function()
        local buf = make_buf()
        atone.setup({
            diff_cur_node = { enabled = true },
            diff_float = { autoclose = false },
        })

        api.nvim_buf_call(buf, function()
            core.open()

            local open_float = get_keymap_callback(core._tree_buf, "gd")
            open_float()
            local diff_float_win = core._centered_diff_win

            api.nvim_set_current_win(core._tree_win)
            vim.wait(100)

            assert.is_true(api.nvim_win_is_valid(diff_float_win))
            assert.are.equal(diff_float_win, core._centered_diff_win)
        end)
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("default diff float config uses 0.8 x 0.8 with autoclose enabled", function()
        local prev = package.loaded["atone.config"]
        package.loaded["atone.config"] = nil
        local fresh_config = require("atone.config")

        assert.are.equal(0.8, fresh_config.opts.diff_float.width)
        assert.are.equal(0.8, fresh_config.opts.diff_float.height)
        assert.is_true(fresh_config.opts.diff_float.autoclose)

        package.loaded["atone.config"] = prev
    end)
end)
