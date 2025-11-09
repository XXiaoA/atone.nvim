local api = vim.api

local M = {}

function M.new_buf()
    local buf_opts = {
        filetype = "atone",
        buftype = "nofile",
        modifiable = false,
        swapfile = false,
    }
    local buf = api.nvim_create_buf(false, true)
    for option, value in pairs(buf_opts) do
        api.nvim_set_option_value(option, value, { buf = buf })
    end
    return buf
end

--- create a new window
---@param mode string `float` or a command passed to the `vim.cmd()`
---@param buf integer
---@param config table?
---@param enter boolean? defaults to true
function M.new_win(mode, buf, config, enter)
    if enter == nil then
        enter = true
    end
    config = config or {}
    local win
    local win_opts = {
        number = false,
        relativenumber = false,
        list = false,
        winfixbuf = true,
        winfixwidth = true,
        wrap = false,
    }

    if mode == "float" then
        win = api.nvim_open_win(buf, enter, config)
        -- close float window after leaving it
        local au
        au = api.nvim_create_autocmd("WinLeave", {
            callback = function()
                if api.nvim_get_current_win() == win then
                    pcall(vim.api.nvim_win_close, win, true)
                    api.nvim_del_autocmd(au)
                elseif not vim.api.nvim_win_is_valid(win) then
                    api.nvim_del_autocmd(au)
                end
            end,
            once = true,
            nested = true,
        })
    else
        local cur = api.nvim_get_current_win()
        vim.cmd(mode .. " +buffer" .. buf)
        win = api.nvim_get_current_win()
        if not enter then
            api.nvim_set_current_win(cur)
        end
        vim.api.nvim_win_set_config(win, config)
    end

    for option, value in pairs(win_opts) do
        api.nvim_set_option_value(option, value, { win = win })
    end

    return win
end

--- Examples:
--- ```lua
-- set_text(0, { "123", "456" }) -- replace the whole buffer
-- set_text(0, { "APPEND" }, -1) -- append at the end
-- set_text(0, { "APPEND2" }, 1, 1) -- append after line 1
-- set_text(0, { "REPLACE" }, 1, 2) -- replace line 2
--- ````
---@param buf integer
---@param texts string[]? nil to clean the buffer
---@param start_lnum integer? defaults to 0
---@param end_lnum integer? defaults to -1
function M.set_text(buf, texts, start_lnum, end_lnum)
    texts = texts or {}
    start_lnum = start_lnum or 0
    end_lnum = end_lnum or -1
    local modifiable = api.nvim_get_option_value("modifiable", { buf = buf })
    api.nvim_set_option_value("modifiable", true, { buf = buf })
    api.nvim_buf_set_lines(buf, start_lnum, end_lnum, true, texts)
    api.nvim_set_option_value("modifiable", modifiable, { buf = buf })
end

---@param mode string|string[]
---@param lhs string|string[]
---@param rhs string|function
---@param opts table?
function M.keymap(mode, lhs, rhs, opts)
    if type(lhs) == "string" then
        lhs = { lhs }
    end
    for _, l in ipairs(lhs) do
        vim.keymap.set(mode, l, rhs, opts)
    end
end

---@param buf integer
---@param higroup string
---@param line string
---@param lnum integer
---@param column integer
function M.color_char(buf, higroup, line, lnum, column)
    local start_byte = vim.str_byteindex(line, "utf-16", column - 1) + 1
    local end_byte = vim.str_byteindex(line, "utf-16", column)
    vim.hl.range(buf, api.nvim_create_namespace("atone"), higroup, { lnum - 1, start_byte - 1 }, { lnum - 1, end_byte - 1 })
end

--- Returns how long ago (from now) a given timestamp was.
---@param past_time integer
function M.time_ago(past_time)
    local now = os.time()
    local diff = now - past_time

    if diff < 60 then
        return "<1 min ago"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return string.format("%d min%s ago", mins, mins > 1 and "s" or "")
    elseif diff < 86400 then
        local hrs = math.floor(diff / 3600)
        return string.format("%d hr%s ago", hrs, hrs > 1 and "s" or "")
    else
        local days = math.floor(diff / 86400)
        return string.format("%d day%s ago", days, days > 1 and "s" or "")
    end
end

return M
