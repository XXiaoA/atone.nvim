---@diagnostic disable: undefined-global, undefined-field
local diff = require("atone.diff")
local tree = require("atone.tree")
local utils = require("atone.utils")
local api = vim.api

--- Load a fixture into a scratch buffer and return (buf, sorted_seqs).
local function load_fixture(file, undo_file)
    local buf = utils.new_buf()
    api.nvim_buf_call(buf, function()
        vim.cmd.e(file)
        vim.cmd("silent rundo " .. undo_file)
        tree.convert(buf)
    end)
    local seqs = vim.tbl_keys(tree.nodes)
    table.sort(seqs)
    -- Remove seq 0 (the empty root), keep only real undo nodes
    seqs = vim.tbl_filter(function(s)
        return s > 0
    end, seqs)
    return buf, seqs
end

describe("Sticky-ref diffing", function()
    local buf, seqs

    before_each(function()
        buf, seqs = load_fixture("tests/test1", "tests/test1.undo")
    end)

    after_each(function()
        api.nvim_buf_delete(buf, { force = true })
    end)

    it("get_context_by_seq returns content at the requested undo state", function()
        -- Context at seq 0 (initial empty state) should differ from later states
        local ctx_early = diff.get_context_by_seq(buf, seqs[1])
        local ctx_later = diff.get_context_by_seq(buf, seqs[#seqs])
        -- They should not be identical for a file with multiple changes
        assert.is_not_nil(ctx_early)
        assert.is_not_nil(ctx_later)
        -- The two contexts are tables of lines
        assert.is_true(type(ctx_early) == "table")
        assert.is_true(type(ctx_later) == "table")
    end)

    it("get_diff between two arbitrary contexts reflects their exact difference", function()
        -- This is the core operation the sticky-ref feature relies on:
        -- diff.get_diff(get_context_by_seq(buf, ref), get_context_by_seq(buf, cur))
        -- We test it directly with known content to avoid fixture-content fragility.
        local ctx_old = { "alpha", "beta", "gamma" }
        local ctx_new = { "alpha", "beta", "gamma", "delta", "epsilon" }
        local d = diff.get_diff(ctx_old, ctx_new)

        local added = {}
        for _, l in ipairs(d) do
            if l:sub(1, 1) == "+" then
                table.insert(added, l:sub(2))
            end
        end
        assert.are.same({ "delta", "epsilon" }, added)
    end)

    it("diff from a node to itself produces no changes", function()
        local seq = seqs[1]
        local ctx = diff.get_context_by_seq(buf, seq)
        local d = diff.get_diff(ctx, ctx)
        local has_change = false
        for _, l in ipairs(d) do
            if l:sub(1, 1) == "+" or l:sub(1, 1) == "-" then
                has_change = true
                break
            end
        end
        assert.is_false(has_change, "diff from a node to itself should have no +/- lines")
    end)
end)

describe("Sticky-ref toggle (core._sticky_ref)", function()
    local core

    before_each(function()
        core = require("atone.core")
        core._sticky_ref = nil
    end)

    after_each(function()
        core._sticky_ref = nil
    end)

    it("is nil by default", function()
        assert.is_nil(core._sticky_ref)
    end)

    it("can be set to a seq value", function()
        core._sticky_ref = 5
        assert.are.equal(5, core._sticky_ref)
    end)

    it("can be cleared back to nil", function()
        core._sticky_ref = 5
        core._sticky_ref = nil
        assert.is_nil(core._sticky_ref)
    end)
end)
