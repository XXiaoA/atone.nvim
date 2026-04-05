local diff = require("atone.diff")
local utils = require("atone.utils")

describe("Diff Module", function()
    describe("extract_change_groups", function()
        it("splits hunk lines into delete/add groups", function()
            local groups = diff.extract_change_groups({
                " context",
                "-old one",
                "-old two",
                "+new one",
                "+new two",
                " context",
                "-left",
                "+right",
            })

            assert.are.equal(2, #groups)
            assert.are.equal(2, #groups[1].del_lines)
            assert.are.equal(2, #groups[1].add_lines)
            assert.are.equal("old one", groups[1].del_lines[1].text)
            assert.are.equal("new two", groups[1].add_lines[2].text)
            assert.are.equal("left", groups[2].del_lines[1].text)
            assert.are.equal("right", groups[2].add_lines[1].text)
        end)

        it("handles alternating - + - + pattern", function()
            local groups = diff.extract_change_groups({
                "-a",
                "+b",
                "-c",
                "+d",
            })

            assert.are.equal(2, #groups)
            assert.are.equal("a", groups[1].del_lines[1].text)
            assert.are.equal("b", groups[1].add_lines[1].text)
            assert.are.equal("c", groups[2].del_lines[1].text)
            assert.are.equal("d", groups[2].add_lines[1].text)
        end)

        it("handles consecutive - - + + pattern", function()
            local groups = diff.extract_change_groups({
                "-a",
                "-b",
                "+c",
                "+d",
            })

            assert.are.equal(1, #groups)
            assert.are.equal(2, #groups[1].del_lines)
            assert.are.equal(2, #groups[1].add_lines)
            assert.are.equal("a", groups[1].del_lines[1].text)
            assert.are.equal("b", groups[1].del_lines[2].text)
            assert.are.equal("c", groups[1].add_lines[1].text)
            assert.are.equal("d", groups[1].add_lines[2].text)
        end)

        it("handles - + + - where trailing delete is orphaned", function()
            local groups = diff.extract_change_groups({
                "-a",
                "+b",
                "+c",
                "-d",
            })

            assert.are.equal(1, #groups)
            assert.are.equal(1, #groups[1].del_lines)
            assert.are.equal(2, #groups[1].add_lines)
            assert.are.equal("a", groups[1].del_lines[1].text)
            assert.are.equal("b", groups[1].add_lines[1].text)
        end)

        it("returns empty for context-only hunk", function()
            local groups = diff.extract_change_groups({
                " context1",
                " context2",
            })

            assert.are.equal(0, #groups)
        end)
    end)

    describe("compute_intra_hunks", function()
        it("computes inline spans for a single-line replacement", function()
            local intra = diff.compute_intra_hunks({
                "-hello world",
                "+hello there",
            })

            assert.is_not_nil(intra)
            assert.is_true(#intra.del_spans >= 1)
            assert.is_true(#intra.add_spans >= 1)
            assert.are.equal(1, intra.del_spans[1].line)
            assert.are.equal(2, intra.add_spans[1].line)
            -- Word-level diff highlights entire changed words
            assert.are.equal(6, intra.del_spans[1].col_start)
            assert.are.equal(11, intra.del_spans[1].col_end)
            assert.are.equal(6, intra.add_spans[1].col_start)
            assert.are.equal(11, intra.add_spans[1].col_end)
        end)

        it("keeps spans inside the changed line body", function()
            local intra = diff.compute_intra_hunks({
                "-prefix old suffix",
                "+prefix new suffix",
            })

            assert.is_not_nil(intra)
            for _, span in ipairs(intra.del_spans) do
                assert.is_true(span.col_start >= 0)
                assert.is_true(span.col_end <= #"prefix old suffix")
                assert.is_true(span.col_start < span.col_end)
            end
            for _, span in ipairs(intra.add_spans) do
                assert.is_true(span.col_start >= 0)
                assert.is_true(span.col_end <= #"prefix new suffix")
                assert.is_true(span.col_start < span.col_end)
            end
            -- Word-level diff highlights "old" → "new"
            assert.are.equal(1, #intra.del_spans)
            assert.are.equal(1, #intra.add_spans)
            assert.are.equal(7, intra.del_spans[1].col_start)
            assert.are.equal(10, intra.del_spans[1].col_end)
            assert.are.equal(7, intra.add_spans[1].col_start)
            assert.are.equal(10, intra.add_spans[1].col_end)
        end)

        it("handles multi-line replacement groups", function()
            local intra = diff.compute_intra_hunks({
                "-alpha one",
                "-beta two",
                "+alpha ONE",
                "+beta TWO",
            })

            assert.is_not_nil(intra)
            assert.is_true(#intra.del_spans >= 2)
            assert.is_true(#intra.add_spans >= 2)
            -- Word-level: "one"→"ONE", "two"→"TWO"
            assert.are.equal(6, intra.del_spans[1].col_start)
            assert.are.equal(9, intra.del_spans[1].col_end)
            assert.are.equal(5, intra.del_spans[2].col_start)
            assert.are.equal(8, intra.del_spans[2].col_end)
        end)

        it("returns nil when there is no add/delete pair", function()
            local intra = diff.compute_intra_hunks({
                " context",
                "+added only",
                " context",
            })

            assert.is_nil(intra)
        end)

        it("handles multibyte UTF-8 characters correctly", function()
            local intra = diff.compute_intra_hunks({
                "-你好",
                "+您好",
            })

            assert.is_not_nil(intra)
            assert.is_true(#intra.del_spans >= 1)
            assert.is_true(#intra.add_spans >= 1)
            assert.are.equal(0, intra.del_spans[1].col_start)
            assert.are.equal(0, intra.add_spans[1].col_start)
            -- Word-level: entire line is one token, so full span
            assert.are.equal(6, intra.del_spans[1].col_end)
            assert.are.equal(6, intra.add_spans[1].col_end)
        end)

        it("snaps multi-byte spans to character boundaries", function()
            -- "αβγ" is a single word token, so the entire line is highlighted
            local intra = diff.compute_intra_hunks({
                "-αβγ",
                "+αδγ",
            })

            assert.is_not_nil(intra)
            -- Single word → entire line highlighted, boundaries are on char boundaries
            assert.is_true(#intra.del_spans >= 1)
            assert.is_true(#intra.add_spans >= 1)
            for _, span in ipairs(intra.del_spans) do
                assert.are.equal(0, span.col_start % 2, "del span start not on char boundary: " .. span.col_start)
                assert.are.equal(0, span.col_end % 2, "del span end not on char boundary: " .. span.col_end)
            end
            for _, span in ipairs(intra.add_spans) do
                assert.are.equal(0, span.col_start % 2, "add span start not on char boundary: " .. span.col_start)
                assert.are.equal(0, span.col_end % 2, "add span end not on char boundary: " .. span.col_end)
            end
        end)
    end)

    describe("char_byte_start / char_byte_end", function()
        it("returns unchanged position at character boundary", function()
            -- "你" = 3 bytes (0-based: 0-2). Boundaries: 0, 3.
            assert.are.equal(0, utils.char_byte_start("你好", 0))
            assert.are.equal(3, utils.char_byte_start("你好", 3))
        end)

        it("snaps mid-character to character start", function()
            -- "你" bytes 0-2, "好" bytes 3-5 (0-based)
            assert.are.equal(0, utils.char_byte_start("你好", 1))
            assert.are.equal(0, utils.char_byte_start("你好", 2))
            assert.are.equal(3, utils.char_byte_start("你好", 4))
        end)

        it("snaps to character end", function()
            -- "你" exclusive end = 3, "好" exclusive end = 6
            assert.are.equal(3, utils.char_byte_end("你好", 0))
            assert.are.equal(3, utils.char_byte_end("你好", 2))
            assert.are.equal(6, utils.char_byte_end("你好", 3))
            assert.are.equal(6, utils.char_byte_end("你好", 5))
        end)

        it("handles ASCII text unchanged", function()
            assert.are.equal(0, utils.char_byte_start("abc", 0))
            assert.are.equal(1, utils.char_byte_start("abc", 1))
            assert.are.equal(1, utils.char_byte_end("abc", 0))
        end)

        it("handles boundary at string end", function()
            assert.are.equal(6, utils.char_byte_start("你好", 6))
            assert.are.equal(6, utils.char_byte_end("你好", 6))
        end)

        it("handles last byte of last character without overflow", function()
            -- "αβγ" = 6 bytes. Last byte (index 5) is second byte of "γ".
            -- char_byte_end should return 6 (string length), not throw.
            assert.are.equal(6, utils.char_byte_end("αβγ", 5))
            -- "你好" = 6 bytes. Last byte (index 5) is third byte of "好".
            assert.are.equal(6, utils.char_byte_end("你好", 5))
            -- Single char edge case
            assert.are.equal(2, utils.char_byte_end("α", 1))
            assert.are.equal(3, utils.char_byte_end("你", 2))
        end)
    end)
end)
