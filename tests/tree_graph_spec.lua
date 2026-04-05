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

describe("default style (ui.compact = false)", function()
    require("atone").setup({ ui = { compact = false } })

    it("test1", function()
        local actaul = get_tree_lines("tests/test1", "tests/test1.undo")
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
        eq(actaul, expected)
    end)

    it("test2", function()
        local actaul = get_tree_lines("tests/test2", "tests/test2.undo")
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
        eq(actaul, expected)
    end)

    it("test3", function()
        local actaul = get_tree_lines("tests/test3", "tests/test3.undo")
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
        eq(actaul, expected)
    end)

    it("test4", function()
        local actaul = get_tree_lines("tests/test4", "tests/test4.undo")
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
        eq(actaul, expected)
    end)

    it("test5", function()
        local actaul = get_tree_lines("tests/test5", "tests/test5.undo")
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
        eq(actaul, expected)
    end)

    it("test6", function()
        local actaul = get_tree_lines("tests/test6", "tests/test6.undo")
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
        eq(actaul, expected)
    end)

    it("test7", function()
        local actaul = get_tree_lines("tests/test7", "tests/test7.undo")
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
        eq(actaul, expected)
    end)

    it("test8", function()
        local actaul = get_tree_lines("tests/test8", "tests/test8.undo")
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
        eq(actaul, expected)
    end)

    it("test9 (seq_last > undolevels)", function()
        local actaul = get_tree_lines("tests/test9", "tests/test9.undo")
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
        eq(actaul, expected)
    end)
end)

describe("compact style (ui.compact = true)", function()
    require("atone").setup({ ui = { compact = true } })

    it("test1", function()
        local actaul = get_tree_lines("tests/test1", "tests/test1.undo")
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
        eq(actaul, expected)
    end)

    it("test2", function()
        local actaul = get_tree_lines("tests/test2", "tests/test2.undo")
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
        eq(actaul, expected)
    end)

    it("test3", function()
        local actaul = get_tree_lines("tests/test3", "tests/test3.undo")
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
        eq(actaul, expected)
    end)

    it("test4", function()
        local actaul = get_tree_lines("tests/test4", "tests/test4.undo")
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
        eq(actaul, expected)
    end)

    it("test5", function()
        local actaul = get_tree_lines("tests/test5", "tests/test5.undo")
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
        eq(actaul, expected)
    end)

    it("test6", function()
        local actaul = get_tree_lines("tests/test6", "tests/test6.undo")
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
        eq(actaul, expected)
    end)

    it("test7", function()
        local actaul = get_tree_lines("tests/test7", "tests/test7.undo")
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
        eq(actaul, expected)
    end)

    it("test8", function()
        local actaul = get_tree_lines("tests/test8", "tests/test8.undo")
        local expected = {
            "●",
            "●",
            "├─●",
            "├─●",
            "│ ●",
            "●─╯",
        }
        eq(actaul, expected)
    end)

    it("test9 (seq_last > undolevels)", function()
        local actaul = get_tree_lines("tests/test9", "tests/test9.undo")
        local expected = {
            "●", -- [,19]
            "│ ●", -- [18]
            "│ │ ●", -- [15]
            "├─│─●", -- [14]
            "● │", -- [13]
            "●─╯", -- [0]
        }
        eq(actaul, expected)
    end)
end)
