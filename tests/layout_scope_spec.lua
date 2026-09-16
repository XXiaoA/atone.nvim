---@diagnostic disable: undefined-global, undefined-field
local atone = require("atone")
local core = require("atone.core")
local config = require("atone.config")
local api = vim.api

local default_scope = config.opts.layout.scope
local default_direction = config.opts.layout.direction
local default_width = config.opts.layout.width
local default_diff_enabled = config.opts.diff_cur_node.enabled
local default_diff_split_percent = config.opts.diff_cur_node.split_percent
local default_diff_width = config.opts.diff_cur_node.width
local original_columns = vim.o.columns
local root_win
local source_buf

local function make_source_split()
    root_win = api.nvim_get_current_win()
    source_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(source_buf, 0, -1, false, { "source" })

    vim.cmd("vsplit")
    local source_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(source_win, source_buf)
    return root_win, source_win
end

local function make_source_horizontal_split()
    root_win = api.nvim_get_current_win()
    source_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(source_buf, 0, -1, false, { "source" })

    vim.cmd("split")
    local source_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(source_win, source_buf)
    return root_win, source_win
end

local function make_middle_source_split()
    root_win = api.nvim_get_current_win()
    source_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(source_buf, 0, -1, false, { "source" })

    vim.cmd("botright vsplit")
    local right_win = api.nvim_get_current_win()
    vim.cmd("aboveleft vsplit")
    local source_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(source_win, source_buf)
    return root_win, source_win, right_win
end

local function cleanup_layout()
    if core._show then
        core.close()
    end

    if root_win then
        for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
            if win ~= root_win and api.nvim_win_is_valid(win) then
                api.nvim_win_close(win, true)
            end
        end
    end
    if root_win and api.nvim_win_is_valid(root_win) then
        api.nvim_set_current_win(root_win)
    end
    if source_buf and api.nvim_buf_is_valid(source_buf) then
        api.nvim_buf_delete(source_buf, { force = true })
    end

    config.opts.layout.scope = default_scope
    config.opts.layout.direction = default_direction
    config.opts.layout.width = default_width
    config.opts.diff_cur_node.enabled = default_diff_enabled
    config.opts.diff_cur_node.split_percent = default_diff_split_percent
    config.opts.diff_cur_node.width = default_diff_width
    vim.o.columns = original_columns
end

describe("layout.scope", function()
    before_each(function()
        vim.o.columns = 200
        root_win = nil
        source_buf = nil
    end)

    after_each(cleanup_layout)

    it("defaults to the existing tabpage-edge layout", function()
        assert.are.equal("tabpage", default_scope)

        local _, source_win = make_source_split()
        atone.setup({
            layout = { direction = "left", width = 0.25 },
            diff_cur_node = { enabled = false },
        })
        api.nvim_set_current_win(source_win)
        core.open()

        assert.are.equal(0, api.nvim_win_get_position(core._tree_win)[2])
    end)

    it("keeps neighbouring windows fixed and sizes the tree from the invoking window", function()
        local neighbour_win, source_win = make_source_split()
        local neighbour_width = api.nvim_win_get_width(neighbour_win)
        local source_width = api.nvim_win_get_width(source_win)

        atone.setup({
            layout = { direction = "left", scope = "window", width = 0.25 },
            diff_cur_node = { enabled = false },
        })
        api.nvim_set_current_win(source_win)
        core.open()

        local expected_tree_width = math.floor(source_width * 0.25 + 0.5)
        assert.are.equal(neighbour_width, api.nvim_win_get_width(neighbour_win))
        assert.are.equal(expected_tree_width, api.nvim_win_get_width(core._tree_win))
    end)

    it("places the tree beside a non-edge invoking window", function()
        local left_win, source_win, right_win = make_middle_source_split()
        local left_width = api.nvim_win_get_width(left_win)
        local right_width = api.nvim_win_get_width(right_win)

        atone.setup({
            layout = { direction = "left", scope = "window", width = 0.25 },
            diff_cur_node = { enabled = false },
        })
        api.nvim_set_current_win(source_win)
        core.open()

        local tree_row, tree_col = unpack(api.nvim_win_get_position(core._tree_win))
        local source_row, source_col = unpack(api.nvim_win_get_position(source_win))

        assert.are.equal(left_width, api.nvim_win_get_width(left_win))
        assert.are.equal(right_width, api.nvim_win_get_width(right_win))
        assert.is_true(tree_col > 0)
        assert.are.equal(source_row, tree_row)
        assert.are.equal(source_col, tree_col + api.nvim_win_get_width(core._tree_win) + 1)
    end)

    it("keeps horizontal siblings outside the invoking window region", function()
        local neighbour_win, source_win = make_source_horizontal_split()
        local neighbour_height = api.nvim_win_get_height(neighbour_win)

        atone.setup({
            layout = { direction = "left", scope = "window", width = 0.25 },
            diff_cur_node = { enabled = true, split_percent = 0.2 },
        })
        api.nvim_set_current_win(source_win)
        core.open()

        assert.are.equal(neighbour_height, api.nvim_win_get_height(neighbour_win))
    end)

    it("returns focus to the invoking window when toggled off", function()
        local _, source_win = make_source_split()
        atone.setup({
            layout = { direction = "left", scope = "window", width = 0.25 },
            diff_cur_node = { enabled = false },
        })
        api.nvim_set_current_win(source_win)
        core.open()
        core.toggle()

        assert.are.equal(source_win, api.nvim_get_current_win())
    end)

    it("keeps a non-adaptive diff preview in the invoking window scope", function()
        local _, source_win = make_source_split()
        local source_width = api.nvim_win_get_width(source_win)

        atone.setup({
            layout = { direction = "left", scope = "window", width = 0.25 },
            diff_cur_node = { enabled = true, split_percent = 0.2, width = 0.5 },
        })
        api.nvim_set_current_win(source_win)
        core.open()

        local diff_config = api.nvim_win_get_config(core._diff_win)
        assert.are.equal(core._dummy_win, diff_config.win)
        assert.are.equal(math.floor(source_width * 0.5 + 0.5), diff_config.width)
        assert.are.equal(api.nvim_win_get_position(core._tree_win)[2], api.nvim_win_get_position(core._dummy_win)[2])
    end)
end)
