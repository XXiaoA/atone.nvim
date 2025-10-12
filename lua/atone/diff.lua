local api, fn = vim.api, vim.fn
local M = {}

--- get the buffer context in nth undo node
--- refer to https://github.com/folke/snacks.nvim/blob/da230e3ca8146da4b73752daaf0a1d07d343c12d/lua/snacks/picker/source/vim.lua#L324
---@param buf integer
---@param seq integer
---@return string[]
function M.get_context_by_seq(buf, seq)
    if seq < 0 then
        return {}
    end

    local result = {}
    local tmp_file = fn.stdpath("cache") .. "/atone-undo"
    local tmp_undo = tmp_file .. ".undo"
    local ei = vim.o.eventignore
    vim.o.eventignore = "all"
    local tmpbuf = fn.bufadd(tmp_file)
    vim.bo[tmpbuf].swapfile = false
    fn.writefile(api.nvim_buf_get_lines(buf, 0, -1, false), tmp_file)
    fn.bufload(tmpbuf)
    api.nvim_buf_call(buf, function()
        vim.cmd("silent wundo! " .. tmp_undo)
    end)
    api.nvim_buf_call(tmpbuf, function()
        ---@diagnostic disable-next-line: param-type-mismatch
        pcall(vim.cmd, "silent rundo " .. tmp_undo)
        vim.cmd("noautocmd silent undo " .. seq)
        result = api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
    end)
    vim.o.eventignore = ei
    vim.api.nvim_buf_delete(tmpbuf, { force = true })
    return result
end

function M.get_diff(ctx1, ctx2)
    ---@diagnostic disable-next-line: deprecated
    local diff = vim.text.diff or vim.diff
    local result = diff(table.concat(ctx1, "\n") .. "\n", table.concat(ctx2, "\n") .. "\n", {
        ctxlen = 3,
        ignore_cr_at_eol = true,
        ignore_whitespace_change_at_eol = true,
        -- indent_heuristic = true,
    })
    ---@diagnostic disable-next-line: param-type-mismatch
    return vim.split(result, "\n")
end

return M
