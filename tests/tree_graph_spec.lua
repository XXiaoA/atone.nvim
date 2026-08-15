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

-- Reverse lookup derived from config: glyph character -> its arcs. Derived
-- instead of hand-written so it cannot drift out of sync with config.
local function build_glyph_arcs()
    local s = require("atone.config").get_graph_symbols()
    local arcs = {}
    for mask, ch in pairs(s.node_glyphs) do
        arcs[ch] = {
            up = mask % 2 == 1,
            down = mask % 4 >= 2,
            left = mask % 8 >= 4,
            right = mask >= 8,
        }
    end
    return arcs
end

-- Render the tree and return the stripped lines.
local function render_lines(file, undo_file, opts)
    -- Pin node_label.custom to false so earlier tests that enabled custom
    -- labels cannot change the rendered output.
    require("atone").setup(vim.tbl_deep_extend("force", opts, {
        ui = { node_label = { custom = false } },
    }))
    return get_tree_lines(file, undo_file)
end

-- Verify that every node glyph is a valid branch commit character and that
-- its arcs are consistent with the graph lines around it: a line above/below
-- or to the left must be reflected in the glyph's up/down/left arc.
local function check_branch_graph_consistency(file, undo_file)
    local tree = require("atone.tree")
    local utils = require("atone.utils")
    local api = vim.api
    local lines, lnum_to_seq, nodes
    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        tree.convert(buf)
        lines = tree.render()
        lnum_to_seq = tree.lnum_to_seq
        nodes = tree.nodes
    end)
    api.nvim_buf_delete(buf, { force = true })

    local s = require("atone.config").get_graph_symbols()
    local glyph_arcs = build_glyph_arcs()
    -- A line above connects only when its bottom edge has an endpoint
    -- (vline/fork); corner/merge arc upward, so a node below them is not
    -- connected. A line below connects when its top edge has an endpoint.
    local is_up_line = { [s.vline] = true, [s.fork] = true }
    local is_down_line = { [s.vline] = true, [s.fork] = true, [s.merge] = true, [s.corner] = true }
    for lnum, seq in pairs(lnum_to_seq) do
        local col = nodes[seq].depth * 2 - 1
        local ch = vim.fn.strcharpart(lines[lnum], col - 1, 1)
        local arcs = glyph_arcs[ch]
        assert(arcs, string.format("node at line %d (seq %d) is not a branch node glyph: %q", lnum, seq, ch))
        local above = lnum > 1 and vim.fn.strcharpart(lines[lnum - 1] or "", col - 1, 1) or ""
        local below = vim.fn.strcharpart(lines[lnum + 1] or "", col - 1, 1) or ""
        local left = col > 1 and vim.fn.strcharpart(lines[lnum], col - 2, 1) or ""
        local right = vim.fn.strcharpart(lines[lnum], col, 1)
        if is_up_line[above] then
            assert(arcs.up, string.format("node at line %d has a line above but no up arc", lnum))
        end
        if is_down_line[below] then
            assert(arcs.down, string.format("node at line %d has a line below but no down arc", lnum))
        end
        if left == s.hline then
            assert(arcs.left, string.format("node at line %d has a line to the left but no left arc", lnum))
        end
        if right == s.hline then
            assert(arcs.right, string.format("node at line %d has a line to the right but no right arc", lnum))
        end
    end
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

        eq(#info.matches, 4)
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

describe("branch symbols (ui.branch_symbols = true)", function()
    local expectations = {
        {
            file = "test1",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "",
                "  ",
                "  ",
                "",
                "",
            },
        },
        {
            file = "test1",
            compact = true,
            lines = {
                "",
                " ",
                " ",
                "  ",
                "  ",
                "",
                "  ",
                "",
            },
        },
        {
            file = "test2",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "",
                "  ",
                "  ",
                " ",
                "   ",
                "",
                "",
                "",
                "",
            },
        },
        {
            file = "test2",
            compact = true,
            lines = {
                "",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "",
                "  ",
                " ",
                "",
                "",
            },
        },
        {
            file = "test3",
            compact = false,
            lines = {
                "",
                "",
                "",
                "",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "   ",
                "   ",
                " ",
                "  ",
                "  ",
                "",
                " ",
                " ",
                " ",
                "",
                "",
                "",
                "",
            },
        },
        {
            file = "test3",
            compact = true,
            lines = {
                "",
                "",
                " ",
                "  ",
                "  ",
                "   ",
                " ",
                "  ",
                "",
                " ",
                "",
                "",
            },
        },
        {
            file = "test4",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                "",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                " ",
                "   ",
                "",
                "",
                "",
                "",
            },
        },
        {
            file = "test4",
            compact = true,
            lines = {
                "",
                " ",
                "",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                " ",
                "",
                "",
            },
        },
        {
            file = "test5",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "",
                " ",
                " ",
                "",
                "",
            },
        },
        {
            file = "test5",
            compact = true,
            lines = {
                "",
                " ",
                "  ",
                "  ",
                "  ",
                "",
                " ",
                "",
            },
        },
        {
            file = "test6",
            compact = false,
            lines = {
                "",
                "",
                "",
                "",
                " ",
                " ",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "  ",
                "  ",
                "",
                "",
                "",
                "",
                "",
                "",
            },
        },
        {
            file = "test6",
            compact = true,
            lines = {
                "",
                "",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                "",
                "",
                "",
            },
        },
        {
            file = "test7",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                "  ",
                "  ",
                "  ",
                " ",
                "  ",
                " ",
                "   ",
                "",
                "",
                "",
                "",
            },
        },
        {
            file = "test7",
            compact = true,
            lines = {
                "",
                " ",
                "  ",
                " ",
                "  ",
                " ",
                "",
                "",
            },
        },
        {
            file = "test8",
            compact = false,
            lines = {
                "",
                "",
                "",
                "",
                " ",
                "",
                " ",
                "",
                " ",
                "",
                "",
            },
        },
        {
            file = "test8",
            compact = true,
            lines = {
                "",
                "",
                "",
                "",
                " ",
                "",
            },
        },
        {
            file = "test9",
            compact = false,
            lines = {
                "",
                "",
                " ",
                " ",
                "  ",
                "  ",
                "",
                " ",
                " ",
                "",
                "",
            },
        },
        {
            file = "test9",
            compact = true,
            lines = {
                "",
                " ",
                "  ",
                "",
                " ",
                "",
            },
        },
    }

    for _, case in ipairs(expectations) do
        it(string.format("%s (compact=%s)", case.file, tostring(case.compact)), function()
            local actual = render_lines("tests/" .. case.file, "tests/" .. case.file .. ".undo", {
                ui = { compact = case.compact, branch_symbols = true },
            })
            eq(actual, case.lines)
        end)
    end
end)

describe("branch symbols on fixed undo data", function()
    local files = { "test1", "test2", "test3", "test4", "test5", "test6", "test7", "test8", "test9" }

    it("node glyphs are consistent with surrounding graph lines", function()
        for _, compact in ipairs({ false, true }) do
            for _, file in ipairs(files) do
                require("atone").setup({ ui = { compact = compact, branch_symbols = true } })
                check_branch_graph_consistency("tests/" .. file, "tests/" .. file .. ".undo")
            end
        end
    end)
end)
