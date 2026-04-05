local api = vim.api
local utils = require("atone.utils")
local M = {}

---@diagnostic disable-next-line: deprecated
local diff_fn = vim.text.diff or vim.diff
local _diffopt_cache = nil

-- Coordinate conventions in this module:
--   vim.text.diff indices: 1-based, inclusive start + count
--   AtoneCharSpan:    0-based, exclusive end (matches extmark convention)
--   split_words tokens: 0-based byte positions (orig_start)
--
-- The flow: vim.diff (1-based) → line_to_orig (0-based) → char_byte_start/end
--           → AtoneCharSpan (0-based exclusive) → caller adds col_offset → extmark

---@class AtoneCharSpan
---@field line integer 1-based line index within the hunk body
---@field col_start integer 0-based column (inclusive)
---@field col_end integer 0-based column (exclusive)

---@class AtoneIntraChanges
---@field add_spans AtoneCharSpan[]
---@field del_spans AtoneCharSpan[]

---@class AtoneChangeGroup
---@field del_lines {idx: integer, text: string}[]
---@field add_lines {idx: integer, text: string}[]

--- Read `diffopt` once and cache the result. Invalidated when `diffopt` changes.
---@return {algorithm?: string, linematch?: integer}
local function parse_diffopt()
    if _diffopt_cache then
        return _diffopt_cache
    end
    local opts = {}
    for _, item in ipairs(vim.split(vim.o.diffopt, ",")) do
        local key, value = item:match("^(%w+):(.+)$")
        if key == "algorithm" then
            opts.algorithm = value
        elseif key == "linematch" then
            opts.linematch = tonumber(value)
        end
    end
    _diffopt_cache = opts
    return opts
end

function M.invalidate_diffopt_cache()
    _diffopt_cache = nil
end

--- get the buffer context in nth undo node
--- refer to https://github.com/folke/snacks.nvim/blob/da230e3ca8146da4b73752daaf0a1d07d343c12d/lua/snacks/picker/source/vim.lua#L324
---@param buf integer
---@param seq integer
---@return string[]
function M.get_context_by_seq(buf, seq)
    if seq < 0 then
        return {}
    end

    -- the tmp file where the undo history is saved
    local tmp_undo_file = os.tmpname()
    local result = {}

    local ei = vim.o.eventignore
    vim.o.eventignore = "all"
    local tmpbuf = api.nvim_create_buf(false, true)
    vim.bo[tmpbuf].swapfile = false
    api.nvim_buf_set_lines(tmpbuf, 0, -1, false, api.nvim_buf_get_lines(buf, 0, -1, false))
    api.nvim_buf_call(buf, function()
        vim.cmd("silent wundo! " .. tmp_undo_file)
    end)
    api.nvim_buf_call(tmpbuf, function()
        ---@diagnostic disable-next-line: param-type-mismatch
        pcall(vim.cmd, "silent rundo " .. tmp_undo_file)
        vim.cmd("noautocmd silent undo " .. seq)
        result = api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
    end)
    vim.o.eventignore = ei
    vim.api.nvim_buf_delete(tmpbuf, { force = true })
    os.remove(tmp_undo_file)
    return result
end

function M.get_diff(ctx1, ctx2)
    ---@diagnostic disable-next-line: deprecated
    local diffopts = parse_diffopt()
    local result = diff_fn(table.concat(ctx1, "\n") .. "\n", table.concat(ctx2, "\n") .. "\n", {
        ctxlen = 3,
        algorithm = diffopts.algorithm,
        ignore_cr_at_eol = true,
        ignore_whitespace_change_at_eol = true,
    })
    ---@diagnostic disable-next-line: param-type-mismatch
    return vim.split(result, "\n")
end

---@param bufnr integer
---@param child integer
---@param parent? integer
function M.get_diff_by_seq(bufnr, child, parent)
    local parent_ctx
    if parent then
        parent_ctx = M.get_context_by_seq(bufnr, parent)
    else
        parent_ctx = {}
    end
    return M.get_diff(M.get_context_by_seq(bufnr, child), parent_ctx)
end

--- Run `vim.diff()` in `indices` mode and normalize the result into named keys.
---@param old_text string
---@param new_text string
---@param diff_opts {algorithm?: string, linematch?: integer}
---@return {old_start: integer, old_count: integer, new_start: integer, new_count: integer}[]
local function byte_diff(old_text, new_text, diff_opts)
    local ok, result = pcall(diff_fn, old_text, new_text, {
        result_type = "indices",
        algorithm = diff_opts.algorithm,
        linematch = diff_opts.linematch,
    })
    if not ok or not result then
        return {}
    end

    local hunks = {}
    for _, hunk in ipairs(result) do
        hunks[#hunks + 1] = {
            old_start = hunk[1],
            old_count = hunk[2],
            new_start = hunk[3],
            new_count = hunk[4],
        }
    end
    return hunks
end

--- Split text into word-level tokens (words + whitespace) for vim.diff.
--- Returns tokens with their 0-based byte start position in the original text.
---@param text string
---@return {text: string, orig_start: integer}[]
local function split_words(text)
    local tokens = {}
    local pos = 1
    local len = #text
    while pos <= len do
        local s, e = text:find("%S+", pos)
        if not s then
            tokens[#tokens + 1] = { text = text:sub(pos), orig_start = pos - 1 }
            break
        end
        if s > pos then
            tokens[#tokens + 1] = { text = text:sub(pos, s - 1), orig_start = pos - 1 }
        end
        tokens[#tokens + 1] = { text = text:sub(s, e), orig_start = s - 1 }
        pos = e + 1
    end
    return tokens
end

--- Map a 1-based line index from vim.diff (each token is one line) to the
--- 0-based byte position in the original text.
---@param tokens {text: string, orig_start: integer}[]
---@param line_1based integer 1-based line index in the joined token text
---@param use_end boolean if true, return the byte position after the token
---@return integer 0-based byte position in the original text
local function line_to_orig(tokens, line_1based, use_end)
    if line_1based < 1 or #tokens == 0 then
        return 0
    end
    if line_1based > #tokens then
        return tokens[#tokens].orig_start + #tokens[#tokens].text
    end
    local tok = tokens[line_1based]
    return use_end and (tok.orig_start + #tok.text) or tok.orig_start
end

--- Compare a deleted line and an added line at word granularity.
--- vim.diff operates on word tokens; hunks are then mapped back to byte
--- positions and snapped to UTF-8 character boundaries.
--- linematch is intentionally stripped — it is a line-level alignment feature.
---@param old_line string
---@param new_line string
---@param del_idx integer
---@param add_idx integer
---@param diff_opts {algorithm?: string, linematch?: integer}
---@return AtoneCharSpan[], AtoneCharSpan[]
local function char_diff_pair(old_line, new_line, del_idx, add_idx, diff_opts)
    local del_spans, add_spans = {}, {}

    local old_tokens = split_words(old_line)
    local new_tokens = split_words(new_line)

    local old_segs, new_segs = {}, {}
    for i, t in ipairs(old_tokens) do
        old_segs[i] = t.text
    end
    for i, t in ipairs(new_tokens) do
        new_segs[i] = t.text
    end
    local old_text = table.concat(old_segs, "\n") .. "\n"
    local new_text = table.concat(new_segs, "\n") .. "\n"

    -- linematch is a line-level alignment option; strip it for word-level diffs.
    local char_opts = { algorithm = diff_opts.algorithm }
    local char_hunks = byte_diff(old_text, new_text, char_opts)

    for _, hunk in ipairs(char_hunks) do
        if hunk.old_count > 0 then
            local start_0 = line_to_orig(old_tokens, hunk.old_start, false)
            local last_0 = line_to_orig(old_tokens, hunk.old_start + hunk.old_count - 1, true) - 1
            del_spans[#del_spans + 1] = {
                line = del_idx,
                col_start = utils.char_byte_start(old_line, start_0),
                col_end = utils.char_byte_end(old_line, last_0),
            }
        end
        if hunk.new_count > 0 then
            local start_0 = line_to_orig(new_tokens, hunk.new_start, false)
            local last_0 = line_to_orig(new_tokens, hunk.new_start + hunk.new_count - 1, true) - 1
            add_spans[#add_spans + 1] = {
                line = add_idx,
                col_start = utils.char_byte_start(new_line, start_0),
                col_end = utils.char_byte_end(new_line, last_0),
            }
        end
    end

    return del_spans, add_spans
end

--- Diff a delete/add block. Matching line counts are paired first; mixed-size
--- replacements fall back to pairing as much as possible in order.
---@param group AtoneChangeGroup
---@param diff_opts {algorithm?: string, linematch?: integer}
---@return AtoneCharSpan[], AtoneCharSpan[]
local function diff_group_native(group, diff_opts)
    local all_del, all_add = {}, {}
    local del_count = #group.del_lines
    local add_count = #group.add_lines

    if del_count == 1 and add_count == 1 then
        return char_diff_pair(
            group.del_lines[1].text,
            group.add_lines[1].text,
            group.del_lines[1].idx,
            group.add_lines[1].idx,
            diff_opts
        )
    end

    local old_texts, new_texts = {}, {}
    for i, l in ipairs(group.del_lines) do
        old_texts[i] = l.text
    end
    for i, l in ipairs(group.add_lines) do
        new_texts[i] = l.text
    end

    local line_hunks = byte_diff(table.concat(old_texts, "\n") .. "\n", table.concat(new_texts, "\n") .. "\n", diff_opts)

    for _, hunk in ipairs(line_hunks) do
        local pairs_count = math.min(hunk.old_count, hunk.new_count)
        for i = 0, pairs_count - 1 do
            local old_i = hunk.old_start + i
            local new_i = hunk.new_start + i
            if group.del_lines[old_i] and group.add_lines[new_i] then
                local del_spans, add_spans = char_diff_pair(
                    group.del_lines[old_i].text,
                    group.add_lines[new_i].text,
                    group.del_lines[old_i].idx,
                    group.add_lines[new_i].idx,
                    diff_opts
                )
                vim.list_extend(all_del, del_spans)
                vim.list_extend(all_add, add_spans)
            end
        end
    end

    return all_del, all_add
end

--- Extract consecutive delete/add groups from a unified diff hunk.
--- Context lines split groups, so inline diff is only computed for actual edits.
---@param hunk_lines string[]
---@return AtoneChangeGroup[]
function M.extract_change_groups(hunk_lines)
    local groups = {}
    local del_buf, add_buf = {}, {}

    for i, line in ipairs(hunk_lines) do
        local prefix = line:sub(1, 1)
        if prefix == "-" then
            if #add_buf > 0 then
                if #del_buf > 0 then
                    groups[#groups + 1] = { del_lines = del_buf, add_lines = add_buf }
                end
                del_buf, add_buf = {}, {}
            end
            del_buf[#del_buf + 1] = { idx = i, text = line:sub(2) }
        elseif prefix == "+" then
            add_buf[#add_buf + 1] = { idx = i, text = line:sub(2) }
        else
            if #del_buf > 0 and #add_buf > 0 then
                groups[#groups + 1] = { del_lines = del_buf, add_lines = add_buf }
            end
            del_buf, add_buf = {}, {}
        end
    end

    if #del_buf > 0 and #add_buf > 0 then
        groups[#groups + 1] = { del_lines = del_buf, add_lines = add_buf }
    end

    return groups
end

--- Compute intra-line diff spans for a unified diff hunk.
--- Columns in returned spans are 0-based and exclusive-end, aligned to the
--- body text (without diff prefix). Callers should add the prefix width to
--- obtain buffer column coordinates.
---@param hunk_lines string[]
---@return AtoneIntraChanges?
function M.compute_intra_hunks(hunk_lines)
    local groups = M.extract_change_groups(hunk_lines)
    if #groups == 0 then
        return nil
    end

    local diff_opts = parse_diffopt()
    local all_add, all_del = {}, {}

    for _, group in ipairs(groups) do
        local del_spans, add_spans = diff_group_native(group, diff_opts)
        vim.list_extend(all_del, del_spans)
        vim.list_extend(all_add, add_spans)
    end

    if #all_add == 0 and #all_del == 0 then
        return nil
    end

    return {
        add_spans = all_add,
        del_spans = all_del,
    }
end
return M
