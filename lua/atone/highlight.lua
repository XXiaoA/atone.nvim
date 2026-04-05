local api = vim.api
local diff = require("atone.diff")

local M = {}
local ns = api.nvim_create_namespace("atone_diff_hl")

--- Detect the TreeSitter language for a buffer's filetype
---@param buf integer
---@return string?
function M.get_lang(buf)
    local ft = vim.bo[buf].filetype
    if not ft or ft == "" then
        return nil
    end
    local lang = vim.treesitter.language.get_lang(ft)
    if not lang then
        return nil
    end
    local ok = pcall(vim.treesitter.language.inspect, lang)
    return ok and lang or nil
end

--- Parse unified diff output into hunk structures.
--- Each hunk contains the 1-based index of its @@ header and the body lines.
---@param diff_lines string[]
---@return { start_idx: integer, lines: string[] }[]
local function parse_hunks(diff_lines)
    local hunks = {}
    local current = nil

    for i, line in ipairs(diff_lines) do
        if line:match("^@@") then
            if current and #current.lines > 0 then
                hunks[#hunks + 1] = current
            end
            current = { start_idx = i, lines = {} }
        elseif current then
            local prefix = line:sub(1, 1)
            if prefix == " " or prefix == "+" or prefix == "-" then
                current.lines[#current.lines + 1] = line
            end
        end
    end

    if current and #current.lines > 0 then
        hunks[#hunks + 1] = current
    end

    return hunks
end

--- Apply TreeSitter extmarks for parsed code lines to the diff buffer.
--- The diff body is reconstructed into plain source code first, then every
--- capture is mapped back into the preview buffer by using `line_map`.
--- When a capture spans across old/new stream boundaries, `line_map[i]` returns
--- nil for the missing row and that segment is skipped — this is correct because
--- the capture belongs to a different parse stream (old vs new code).
---@param bufnr integer the diff display buffer
---@param code_lines string[] reconstructed code without diff prefix
---@param lang string TreeSitter language name
---@param line_map table<integer, integer> code line index (0-based) -> buffer row (0-based)
---@param col_offset integer column offset to skip the diff prefix
local function apply_ts_highlights(bufnr, code_lines, lang, line_map, col_offset)
    local code = table.concat(code_lines, "\n")
    if code == "" then
        return
    end

    local ok, parser_obj = pcall(vim.treesitter.get_string_parser, code, lang)
    if not ok or not parser_obj then
        return
    end

    local trees = parser_obj:parse(true)
    if not trees or #trees == 0 then
        return
    end

    -- Iterate all trees including injected languages
    parser_obj:for_each_tree(function(tree, ltree)
        local tree_lang = ltree:lang()
        local query = vim.treesitter.query.get(tree_lang, "highlights")
        if not query then
            return
        end

        for id, node, _ in query:iter_captures(tree:root(), code) do
            local capture = query.captures[id]
            -- Skip spell-related captures that are not visual highlights
            if capture ~= "spell" and capture ~= "nospell" then
                local sr, sc, er, ec = node:range()

                -- Iterate through every code line this capture covers
                for i = sr, er do
                    local buf_row = line_map[i]
                    if buf_row then
                        local start_col = (i == sr) and sc or 0
                        local end_col = (i == er) and ec or -1 -- -1 means end of line

                        -- For rows that extend to end-of-line (not the capture's end row),
                        -- use end_row = buf_row+1 / end_col = 0 so the entire line is
                        -- covered. Without an explicit range, nvim_buf_set_extmark
                        -- produces a zero-width mark that doesn't highlight anything.
                        local erow = (end_col == -1) and (buf_row + 1) or buf_row
                        local ecol = (end_col == -1) and 0 or (end_col + col_offset)
                        pcall(api.nvim_buf_set_extmark, bufnr, ns, buf_row, start_col + col_offset, {
                            end_row = erow,
                            end_col = ecol,
                            hl_group = "@" .. capture .. "." .. tree_lang,
                            priority = 100,
                        })
                    end
                end
            end
        end
    end)
end

---@param bufnr integer
---@param buf_row integer
---@param start_col integer 0-based buffer column
---@param end_col integer 0-based exclusive buffer column
---@param hl_group string
local function apply_inline_extmark(bufnr, buf_row, start_col, end_col, hl_group)
    if start_col >= end_col then
        return
    end
    pcall(api.nvim_buf_set_extmark, bufnr, ns, buf_row, start_col, {
        end_row = buf_row,
        end_col = end_col,
        hl_group = hl_group,
        priority = 80,
    })
end

--- Apply diff preview highlighting to the buffer.
--- All columns are 0-based, exclusive end.
---@param bufnr integer the diff display buffer
---@param diff_lines string[] unified diff lines (output of vim.diff / vim.text.diff)
---@param lang string? TreeSitter language for the source file
---@param opts? {inline_diff?: boolean, treesitter?: boolean}
function M.apply(bufnr, diff_lines, lang, opts)
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    if #diff_lines == 0 then
        return
    end

    opts = opts or {}
    local hunks = parse_hunks(diff_lines)
    --- for standard unified diff (+/- or space)
    local col_offset = 1

    for _, hunk in ipairs(hunks) do
        -- Inline diff is computed per hunk so the exact spans can be applied
        -- while we are already iterating over the diff body lines below.
        local intra = opts.inline_diff and diff.compute_intra_hunks(hunk.lines) or nil
        local inline_spans = {}
        if intra then
            for _, span in ipairs(intra.add_spans) do
                inline_spans[span.line] = inline_spans[span.line] or {}
                inline_spans[span.line][#inline_spans[span.line] + 1] = {
                    start_col = span.col_start + col_offset,
                    end_col = span.col_end + col_offset,
                    hl_group = "AtoneDiffAddInline",
                }
            end
            for _, span in ipairs(intra.del_spans) do
                inline_spans[span.line] = inline_spans[span.line] or {}
                inline_spans[span.line][#inline_spans[span.line] + 1] = {
                    start_col = span.col_start + col_offset,
                    end_col = span.col_end + col_offset,
                    hl_group = "AtoneDiffDeleteInline",
                }
            end
        end

        -- Reconstruct separate code streams for the "new" (context + added) and
        -- "old" (context + removed) sides. Context lines are included in both
        -- streams so the TreeSitter parser sees syntactically complete code.
        local new_code, new_map = {}, {}
        local old_code, old_map = {}, {}

        for i, line in ipairs(hunk.lines) do
            local prefix = line:sub(1, col_offset)
            local stripped = line:sub(col_offset + 1)
            -- hunk.start_idx is 1-based index of @@ in diff_lines;
            -- buffer rows are 0-based, so body line i maps to row (start_idx + i - 1)
            local buf_row = hunk.start_idx + i - 1

            if prefix == "+" then
                new_map[#new_code] = buf_row
                new_code[#new_code + 1] = stripped
            elseif prefix == "-" then
                old_map[#old_code] = buf_row
                old_code[#old_code + 1] = stripped
            else
                -- context line belongs to both streams
                new_map[#new_code] = buf_row
                new_code[#new_code + 1] = stripped
                old_map[#old_code] = buf_row
                old_code[#old_code + 1] = stripped
            end

            if prefix == "+" or prefix == "-" then
                local hl_group = prefix == "+" and "AtoneDiffAdd" or "AtoneDiffDelete"
                pcall(api.nvim_buf_set_extmark, bufnr, ns, buf_row, 0, {
                    end_row = buf_row + 1,
                    end_col = 0,
                    hl_group = hl_group,
                    hl_eol = true,
                    priority = 70,
                })
            end

            if inline_spans[i] then
                for _, span in ipairs(inline_spans[i]) do
                    apply_inline_extmark(bufnr, buf_row, span.start_col, span.end_col, span.hl_group)
                end
            end
        end

        if opts.treesitter and lang then
            apply_ts_highlights(bufnr, new_code, lang, new_map, col_offset)
            apply_ts_highlights(bufnr, old_code, lang, old_map, col_offset)
        end
    end
end

return M
