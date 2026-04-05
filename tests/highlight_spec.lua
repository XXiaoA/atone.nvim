local api = vim.api
local atone = require("atone")
local highlight = require("atone.highlight")
local utils = require("atone.utils")

describe("Highlight Module", function()
    it("setup creates correct inline highlight groups", function()
        assert.is_true(utils.lighten(0x406020, 0.15) > 0x406020)
        assert.is_true(utils.darken(0x406020, 0.15) < 0x406020)

        local original_background = vim.o.background
        local original_diff_add = api.nvim_get_hl(0, { name = "DiffAdd", link = false })

        atone.setup({})
        api.nvim_set_hl(0, "DiffAdd", { bg = 0x406020 })
        vim.o.background = "dark"
        vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
        local dark_base = api.nvim_get_hl(0, { name = "DiffAdd", link = false })
        local dark_inline = api.nvim_get_hl(0, { name = "AtoneDiffAddInline", link = false })
        assert.is_true(dark_inline.bg > dark_base.bg)

        vim.o.background = "light"
        vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
        local light_base = api.nvim_get_hl(0, { name = "DiffAdd", link = false })
        local light_inline = api.nvim_get_hl(0, { name = "AtoneDiffAddInline", link = false })
        assert.is_true(light_inline.bg < light_base.bg)

        vim.o.background = original_background
        api.nvim_set_hl(0, "DiffAdd", original_diff_add)
    end)

    it("applies line and inline diff highlights without TreeSitter", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1 +1 @@",
            "-hello world",
            "+hello there",
        }

        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)
        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local groups = {}
        for _, extmark in ipairs(extmarks) do
            local details = extmark[4]
            if details and details.hl_group then
                groups[details.hl_group] = true
            end
        end

        assert.is_true(groups.AtoneDiffDelete)
        assert.is_true(groups.AtoneDiffAdd)
        assert.is_true(groups.AtoneDiffDeleteInline)
        assert.is_true(groups.AtoneDiffAddInline)

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("aligns inline highlights correctly by skipping the diff prefix", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1 +1 @@",
            "-abc",
            "+axc",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local add_inline_mark = nil
        for _, mark in ipairs(extmarks) do
            if mark[4] and mark[4].hl_group == "AtoneDiffAddInline" then
                add_inline_mark = mark
                break
            end
        end

        assert.is_not_nil(add_inline_mark)
        -- Buffer line 2 is "+axc". Word-level diff highlights the entire word.
        -- Prefix "+" is at col 0, "axc" spans cols 1-4.
        assert.are.equal(2, add_inline_mark[2]) -- row 2 (0-based)
        assert.are.equal(1, add_inline_mark[3]) -- col 1 (after prefix)
        assert.are.equal(4, add_inline_mark[4].end_col) -- col 4 (end of "axc")

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("does not leak multi-line TreeSitter highlights to intervening lines", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1,2 +1,5 @@",
            " local x = {",
            "+  new1 = 1,",
            "-  old = 1,",
            "+  new2 = 2,",
            " }",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, "lua", {
            treesitter = true,
            inline_diff = false,
        })

        local marks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })

        for _, mark in ipairs(marks) do
            local row = mark[2]
            local details = mark[4]
            local hl = details.hl_group or ""

            if hl:match("^@.*%.lua$") then
                local end_row = details.end_row or row
                assert.is_false(
                    row < 3 and end_row > 3,
                    "Found leaked multi-line highlight: " .. hl .. " from row " .. row .. " to " .. end_row
                )
            end
        end

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("inline diff covers full multi-byte characters", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1 +1 @@",
            "-αβγ",
            "+αδγ",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        -- Word-level diff: "αβγ" is one token, so entire word is highlighted.
        -- Buffer has "+αδγ": prefix '+' at col 0, then 3x2-byte chars at cols 1-2, 3-4, 5-6.
        -- The span starts at col 1 (after prefix), which is the start of "α".
        local found = false
        for _, mark in ipairs(extmarks) do
            local details = mark[4]
            if details and (details.hl_group == "AtoneDiffAddInline" or details.hl_group == "AtoneDiffDeleteInline") then
                found = true
                local start_col = mark[3]
                local end_col = details.end_col
                -- After prefix offset (1), char boundaries are at odd columns: 1, 3, 5, 7.
                local prefix = 1
                assert.are.equal(prefix % 2, start_col % 2, "inline extmark start not on char boundary: col " .. start_col)
                assert.are.equal(prefix % 2, end_col % 2, "inline extmark end not on char boundary: col " .. end_col)
            end
        end
        assert.is_true(found, "expected at least one inline extmark")

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("inline extmarks have explicit end_row", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1 +1 @@",
            "-abc",
            "+axc",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local marks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        for _, m in ipairs(marks) do
            local d = m[4]
            if d and (d.hl_group == "AtoneDiffAddInline" or d.hl_group == "AtoneDiffDeleteInline") then
                assert.is_not_nil(d.end_row, "inline extmark missing end_row")
                assert.are.equal(m[2], d.end_row, "inline extmark end_row should equal buf_row")
            end
        end

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles multi-hunk diff correctly", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1,2 +1,2 @@",
            "-old line 1",
            "+new line 1",
            " context",
            "@@ -10 +10 @@",
            "-old line 10",
            "+new line 10",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local groups = {}
        for _, mark in ipairs(extmarks) do
            local d = mark[4]
            if d and d.hl_group then
                groups[d.hl_group] = (groups[d.hl_group] or 0) + 1
            end
        end

        assert.is_not_nil(groups.AtoneDiffDelete)
        assert.is_not_nil(groups.AtoneDiffAdd)
        assert.is_not_nil(groups.AtoneDiffDeleteInline)
        assert.is_not_nil(groups.AtoneDiffAddInline)

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles pure delete hunk without add lines", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1,2 +1 @@",
            "-deleted line",
            " context",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local has_delete = false
        for _, mark in ipairs(extmarks) do
            if mark[4] and mark[4].hl_group == "AtoneDiffDelete" then
                has_delete = true
                break
            end
        end
        assert.is_true(has_delete)

        api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles pure add hunk without delete lines", function()
        local buf = api.nvim_create_buf(false, true)
        local diff_lines = {
            "@@ -1 +1,2 @@",
            " context",
            "+added line",
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, diff_lines)

        highlight.apply(buf, diff_lines, nil, {
            treesitter = false,
            inline_diff = true,
        })

        local extmarks = api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
        local has_add = false
        for _, mark in ipairs(extmarks) do
            if mark[4] and mark[4].hl_group == "AtoneDiffAdd" then
                has_add = true
                break
            end
        end
        assert.is_true(has_add)

        api.nvim_buf_delete(buf, { force = true })
    end)
end)
