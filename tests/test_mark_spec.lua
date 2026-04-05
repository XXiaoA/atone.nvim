local stub = require("luassert.stub")
local mark = require("atone.mark")
local config = require("atone.config")

-- Mock config
config.opts = {
    marks = {
        persist = false,
        persist_path = "/tmp/atone_marks.json",
        finders = { "builtin" },
    },
}

-- Mock vim.notify
local notify_spy = stub(vim, "notify")
-- Mock vim.fn.fnamemodify
local original_fnamemodify = vim.fn.fnamemodify
vim.fn.fnamemodify = function(path, _)
    return path
end

-- Helper to reset marks
local function reset_marks()
    mark._marks = {}
end

describe("Mark Module", function()
    before_each(function()
        reset_marks()
        notify_spy:clear()
    end)

    after_each(function()
        vim.fn.fnamemodify = original_fnamemodify
    end)

    describe("Input Parsing", function()
        it("should parse N:name correctly", function()
            local name, slot = mark.parse_input("1:my_mark")
            assert.are.equal("my_mark", name)
            assert.are.equal(1, slot)
        end)

        it("should parse N correctly as both name and slot", function()
            local name, slot = mark.parse_input("5")
            assert.are.equal("5", name)
            assert.are.equal(5, slot)
        end)

        it("should parse name correctly without slot", function()
            local name, slot = mark.parse_input("only_name")
            assert.are.equal("only_name", name)
            assert.is_nil(slot)
        end)

        it("should return nil for invalid slot format", function()
            local name, slot = mark.parse_input("10:too_long_slot")
            assert.is_nil(name)
            assert.is_nil(slot)

            name, slot = mark.parse_input("11")
            assert.is_nil(name)
            assert.is_nil(slot)
        end)
    end)

    describe("Mark Management", function()
        local filepath = "/tmp/test_file"

        it("should set and retrieve a mark", function()
            mark.set_mark(filepath, 10, "m1", 1)
            local m = mark.get_by_slot(filepath, 1)
            assert.are.equal(10, m.seq)
            assert.are.equal("m1", m.name)
        end)

        it("should clear old slot when assigning to new mark", function()
            mark.set_mark(filepath, 10, "m1", 1)
            mark.set_mark(filepath, 20, "m2", 1) -- Same slot

            assert.is_nil(mark.get_marks(filepath)["m1"].slot, "m1's slot should be cleared")
            assert.are.equal(1, mark.get_marks(filepath)["m2"].slot)
        end)

        it("should overwrite mark with the same name", function()
            mark.set_mark(filepath, 10, "m1", 1)
            mark.set_mark(filepath, 20, "m1", 2) -- Same name, different seq and slot

            local marks = mark.get_marks(filepath)
            assert.are.equal(20, marks["m1"].seq)
            assert.are.equal(2, marks["m1"].slot)
        end)

        it("should retrieve multiple marks for same seq", function()
            mark.set_mark(filepath, 10, "m1")
            mark.set_mark(filepath, 10, "m2")

            local marks = mark.get_by_seq(filepath, 10)
            assert.are.equal(2, #marks)
        end)

        it("should delete a specific mark", function()
            mark.set_mark(filepath, 10, "m1")
            mark.delete_mark(filepath, "m1")
            assert.is_nil(mark.get_marks(filepath)["m1"])
        end)

        it("should delete all marks for a file", function()
            mark.set_mark(filepath, 10, "m1")
            mark.set_mark(filepath, 20, "m2")
            mark.delete_all_marks(filepath)
            assert.is_true(vim.tbl_isempty(mark.get_marks(filepath)))
        end)
    end)

    describe("Label Building", function()
        local filepath = "/tmp/test_file"

        it("should build labels correctly", function()
            mark.set_mark(filepath, 10, "1", 1) -- Slot as name
            mark.set_mark(filepath, 20, "named", 2) -- Named slot
            mark.set_mark(filepath, 30, "no_slot") -- No slot

            local labels = mark.build_labels(filepath)
            assert.are.equal("{1}", labels[10])
            assert.are.equal("{2:named}", labels[20])
            assert.are.equal("{no_slot}", labels[30])
        end)

        it("should merge labels for same seq", function()
            mark.set_mark(filepath, 10, "m1", 1)
            mark.set_mark(filepath, 10, "m2", 2)

            local labels = mark.build_labels(filepath)
            assert.are.equal("{1:m1} {2:m2}", labels[10])
        end)
    end)

    describe("Pruning", function()
        it("should remove marks with invalid seq", function()
            local filepath = "/tmp/test_file"
            mark.set_mark(filepath, 100, "valid")
            mark.set_mark(filepath, 200, "invalid")

            local valid_nodes = { [100] = { seq = 100 } }
            mark.prune(filepath, valid_nodes)

            local marks = mark.get_marks(filepath)
            assert.is_not_nil(marks["valid"])
            assert.is_nil(marks["invalid"])
        end)
    end)

    describe("Persistence (Simulated)", function()
        it("should load empty data if file doesn't exist", function()
            -- Mock io.open to return nil (file not found)
            local old_open = io.open
            io.open = function()
                return nil
            end

            mark.load()
            assert.is_true(vim.tbl_isempty(mark._marks))

            io.open = old_open
        end)

        it("should handle corrupted JSON gracefully", function()
            local old_open = io.open
            io.open = function()
                return {
                    read = function()
                        return "invalid json"
                    end,
                    close = function() end,
                }
            end

            mark.load()
            assert.is_true(vim.tbl_isempty(mark._marks))

            io.open = old_open
        end)
    end)
end)
