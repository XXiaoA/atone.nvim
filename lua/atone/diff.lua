local api = vim.api
local M = {}

local context_cache = {}
--- get the buffer context in nth undo node
--- refer to https://github.com/folke/snacks.nvim/blob/da230e3ca8146da4b73752daaf0a1d07d343c12d/lua/snacks/picker/source/vim.lua#L324
---@param buf integer
---@param seq integer
---@return string[]
function M.get_context_by_seq(buf, seq)
    if seq < 0 then
        return {}
    end
    context_cache[buf] = context_cache[buf] or {}
    if context_cache[buf][seq] == nil then
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
        context_cache[buf][seq] = result
    end
    return context_cache[buf][seq]
end

local diff_cache = {}
function M.get_diff(ctx1, ctx2)
    local str1 = table.concat(ctx1, "\n") .. "\n"
    local str2 = table.concat(ctx2, "\n") .. "\n"
    diff_cache[str1] = diff_cache[str1] or {}
    if diff_cache[str1][str2] == nil then
        ---@diagnostic disable-next-line: deprecated
        local diff = vim.text.diff or vim.diff

        local result = diff(str1, str2, {
            ctxlen = 3,
            ignore_cr_at_eol = true,
            ignore_whitespace_change_at_eol = true,
            -- indent_heuristic = true,
        })
        ---@diagnostic disable-next-line: param-type-mismatch
        diff_cache[str1][str2] = vim.split(result, "\n")
    end
    return diff_cache[str1][str2]
end

return M
