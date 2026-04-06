---@diagnostic disable: undefined-global, undefined-field
local eq = assert.are.same
local utils = require("atone.utils")
local tree = require("atone.tree")
local api = vim.api

local function get_tree_lines(file, undo_file)
    local result
    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        tree.convert(buf)
        local buf_lines = tree.render()
        result = vim.tbl_map(function(s)
            return (s:gsub("%[%d+%].*$", ""):gsub("%s+$", ""))
        end, buf_lines)
    end)
    api.nvim_buf_delete(buf, { force = true })
    return result
end

local function get_tree_label_line(file, undo_file, line_nr)
    local result
    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        tree.convert(buf)
        result = tree.render()[line_nr]
    end)
    api.nvim_buf_delete(buf, { force = true })
    return result
end

local function render_custom_line(file, undo_file, line_nr, formatter)
    local atone = require("atone")
    local core = require("atone.core")
    local mark = require("atone.mark")
    local result
    atone.setup({
        ui = { compact = false, node_label = { custom = true, formatter = formatter, extmark_opts = { strict = false } } },
    })

    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        core.open()
        result = api.nvim_buf_get_lines(core._tree_buf, line_nr - 1, line_nr, false)[1]
        local filepath = utils.buf_filepath(buf)
        mark.delete_all_marks(filepath)
        core.close()
    end)
    api.nvim_buf_delete(buf, { force = true })
    return result
end

local function open_tree_and_collect(file, undo_file, opts)
    local atone = require("atone")
    local core = require("atone.core")
    local result = {}
    atone.setup(opts or {})

    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        core.open()
        result.matches = api.nvim_win_call(core._tree_win, function()
            return vim.fn.getmatches()
        end)
        result.extmarks = api.nvim_buf_get_extmarks(core._tree_buf, -1, 0, -1, { details = true })
        core.close()
    end)
    api.nvim_buf_delete(buf, { force = true })
    return result
end

local function measure_custom_formatter_calls()
    local atone = require("atone")
    local core = require("atone.core")
    local calls = 0
    local result = {}

    atone.setup({
        ui = {
            compact = false,
            node_label = {
                custom = true,
                formatter = function(ctx)
                    calls = calls + 1
                    return string.format("[%d] %s", ctx.seq, ctx.h_time)
                end,
                extmark_opts = { strict = false },
            },
        },
        diff_cur_node = { enabled = false },
    })

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_call(buf, function()
        vim.bo[buf].undolevels = 64
        vim.bo[buf].buftype = ""
        vim.bo[buf].modifiable = true
        vim.bo[buf].swapfile = false
        api.nvim_buf_set_lines(buf, 0, -1, false, { "start" })
        local i = 1
        repeat
            api.nvim_buf_set_lines(buf, -1, -1, false, { "line " .. i })
            vim.o.undolevels = vim.o.undolevels
            i = i + 1
            tree.convert(buf)
        until tree.total > 12 or i > 200

        core.open()
        local wininfo = vim.fn.getwininfo(core._tree_win)[1]
        local visible_rows = wininfo.botline - wininfo.topline + 1
        local total = tree.total
        result.open_calls = calls
        result.visible_rows = visible_rows
        result.total = total
        result.generated_steps = i - 1
        api.nvim_win_set_cursor(core._tree_win, { math.min(api.nvim_buf_line_count(core._tree_buf), visible_rows + 5), 0 })
        tree.render_visible_labels(core._tree_buf, core._tree_win)
        result.after_scroll_calls = calls
        core.close()
    end)
    api.nvim_buf_delete(buf, { force = true })

    return result
end

describe("default labels", function()
    require("atone").setup({ ui = { compact = false, node_label = { custom = false } } })

    it("keeps the fixed label format when custom labels are disabled", function()
        local line = get_tree_label_line("tests/test1", "tests/test1.undo", 15)
        assert.matches("^●%s+%[0%]%s+Original", line)
    end)
end)

describe("custom label context", function()
    it("exposes bookmark to the formatter", function()
        local mark = require("atone.mark")
        local filepath = vim.fn.fnamemodify("tests/test1", ":p")
        mark.delete_all_marks(filepath)
        mark.set_mark(filepath, 7, "leaf")

        local line = render_custom_line("tests/test1", "tests/test1.undo", 1, function(ctx)
            return string.format("[%d] %s %s", ctx.seq, ctx.h_time, ctx.bookmark or "")
        end)

        assert.matches("%{leaf%}", line)
        mark.delete_all_marks(filepath)
    end)

    it("does not register matchadd highlights in custom mode", function()
        local info = open_tree_and_collect("tests/test1", "tests/test1.undo", {
            ui = {
                compact = false,
                node_label = {
                    custom = true,
                    formatter = function(ctx)
                        return string.format("[%d] %s", ctx.seq, ctx.h_time)
                    end,
                },
            },
        })

        eq(#info.matches, 0)
    end)

    it("uses extmarks for chunk highlight groups", function()
        local info = open_tree_and_collect("tests/test1", "tests/test1.undo", {
            ui = {
                compact = false,
                node_label = {
                    custom = true,
                    formatter = function(ctx)
                        return {
                            "[",
                            { ctx.seq, "AtoneSeq" },
                            "] ",
                            { ctx.h_time, "Comment" },
                        }
                    end,
                    extmark_opts = { strict = false },
                },
            },
        })

        assert.is_true(#info.extmarks > 0)
    end)

    it("renders custom labels on demand for the viewport", function()
        local stats = measure_custom_formatter_calls()

        assert.is_true(stats.generated_steps > stats.visible_rows)
        assert.is_true(stats.total > stats.visible_rows)
        assert.is_true(stats.open_calls < stats.total)
        assert.is_true(stats.open_calls <= stats.visible_rows)
        assert.is_true(stats.after_scroll_calls > stats.open_calls)
    end)
end)

describe("fixed label mode", function()
    it("registers matchadd highlights in default mode", function()
        local info = open_tree_and_collect("tests/test1", "tests/test1.undo", {
            ui = { compact = false, node_label = { custom = false } },
        })

        eq(#info.matches, 3)
    end)
end)

describe("default style (ui.compact = false)", function()
    require("atone").setup({ ui = { compact = false } })

    it("test1", function()
        local actual = get_tree_lines("tests/test1", "tests/test1.undo")
        local expected = {
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "├─│─│─●",
            "│ │ │",
            "● │ │",
            "├─┴─╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test2", function()
        local actual = get_tree_lines("tests/test2", "tests/test2.undo")
        local expected = {
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "├─│─│─●",
            "│ │ │",
            "● │ │",
            "├─╯ │",
            "●   │",
            "├───╯",
            "●",
            "│",
            "●",
        }
        eq(actual, expected)
    end)

    it("test3", function()
        local actual = get_tree_lines("tests/test3", "tests/test3.undo")
        local expected = {
            "●",
            "│",
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "● │ │",
            "│ │ │",
            "│ │ │ ●",
            "│ │ │ │",
            "│ ├─│─●",
            "│ │ │",
            "│ ● │",
            "├─│─╯",
            "● │",
            "│ │",
            "● │",
            "├─╯",
            "●",
            "│",
            "●",
        }
        eq(actual, expected)
    end)

    it("test4", function()
        local actual = get_tree_lines("tests/test4", "tests/test4.undo")
        local expected = {
            "●",
            "│",
            "│ ●",
            "│ │",
            "├─│─●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "● │ │",
            "├─╯ │",
            "●   │",
            "├───╯",
            "●",
            "│",
            "●",
        }
        eq(actual, expected)
    end)

    it("test5", function()
        local actual = get_tree_lines("tests/test5", "tests/test5.undo")
        local expected = {
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "│ │ │",
            "● │ │",
            "│ │ │",
            "├─│─│─●",
            "│ ├─╯",
            "│ ●",
            "├─╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test6", function()
        local actual = get_tree_lines("tests/test6", "tests/test6.undo")
        local expected = {
            "●",
            "│",
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ ● │",
            "│ │ │",
            "● │ │",
            "├─┴─╯",
            "●",
            "│",
            "●",
            "│",
            "●",
        }
        eq(actual, expected)
    end)

    it("test7", function()
        local actual = get_tree_lines("tests/test7", "tests/test7.undo")
        local expected = {
            "●",
            "│",
            "│ ●",
            "│ │",
            "│ │ ●",
            "│ │ │",
            "│ │ ●",
            "├─╯ │",
            "│ ● │",
            "├─╯ │",
            "●   │",
            "├───╯",
            "●",
            "│",
            "●",
        }
        eq(actual, expected)
    end)

    it("test8", function()
        local actual = get_tree_lines("tests/test8", "tests/test8.undo")
        local expected = {
            "●",
            "│",
            "●",
            "│",
            "│ ●",
            "├─╯",
            "│ ●",
            "├─╯",
            "│ ●",
            "├─╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test9 (seq_last > undolevels)", function()
        local actual = get_tree_lines("tests/test9", "tests/test9.undo")
        local expected = {
            "●", -- [,19]
            "│",
            "│ ●", -- [18]
            "│ │",
            "│ │ ●", -- [15]
            "│ │ │",
            "├─│─●", -- [14]
            "│ │",
            "● │", -- [13]
            "├─╯",
            "●", -- [0]
        }
        eq(actual, expected)
    end)
end)

describe("compact style (ui.compact = true)", function()
    require("atone").setup({ ui = { compact = true } })

    it("test1", function()
        local actual = get_tree_lines("tests/test1", "tests/test1.undo")
        local expected = {
            "●",
            "│ ●",
            "│ ●",
            "│ │ ●",
            "│ │ ●",
            "├─│─│─●",
            "● │ │",
            "●─┴─╯",
        }
        eq(actual, expected)
    end)

    it("test2", function()
        local actual = get_tree_lines("tests/test2", "tests/test2.undo")
        local expected = {
            "●",
            "│ ●",
            "│ ●",
            "│ │ ●",
            "│ │ ●",
            "│ │ ●",
            "├─│─│─●",
            "● │ │",
            "●─╯ │",
            "●───╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test3", function()
        local actual = get_tree_lines("tests/test3", "tests/test3.undo")
        local expected = {
            "●",
            "●",
            "│ ●",
            "│ │ ●",
            "● │ │",
            "│ │ │ ●",
            "│ ├─│─●",
            "│ ● │",
            "●─│─╯",
            "● │",
            "●─╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test4", function()
        local actual = get_tree_lines("tests/test4", "tests/test4.undo")
        local expected = {
            "●",
            "│ ●",
            "├─│─●",
            "│ │ ●",
            "│ │ ●",
            "│ │ ●",
            "│ │ ●",
            "● │ │",
            "●─╯ │",
            "●───╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test5", function()
        local actual = get_tree_lines("tests/test5", "tests/test5.undo")
        local expected = {
            "●",
            "│ ●",
            "│ │ ●",
            "│ │ ●",
            "● │ │",
            "├─│─│─●",
            "│ ●─╯",
            "●─╯",
        }
        eq(actual, expected)
    end)

    it("test6", function()
        local actual = get_tree_lines("tests/test6", "tests/test6.undo")
        local expected = {
            "●",
            "●",
            "│ ●",
            "│ ●",
            "│ │ ●",
            "│ ● │",
            "● │ │",
            "●─┴─╯",
            "●",
            "●",
        }
        eq(actual, expected)
    end)

    it("test7", function()
        local actual = get_tree_lines("tests/test7", "tests/test7.undo")
        local expected = {
            "●",
            "│ ●",
            "│ │ ●",
            "├─╯ ●",
            "│ ● │",
            "●─╯ │",
            "●───╯",
            "●",
        }
        eq(actual, expected)
    end)

    it("test8", function()
        local actual = get_tree_lines("tests/test8", "tests/test8.undo")
        local expected = {
            "●",
            "●",
            "├─●",
            "├─●",
            "│ ●",
            "●─╯",
        }
        eq(actual, expected)
    end)

    it("test9 (seq_last > undolevels)", function()
        local actual = get_tree_lines("tests/test9", "tests/test9.undo")
        local expected = {
            "●", -- [,19]
            "│ ●", -- [18]
            "│ │ ●", -- [15]
            "├─│─●", -- [14]
            "● │", -- [13]
            "●─╯", -- [0]
        }
        eq(actual, expected)
    end)
end)
