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
---@param config { win_config?: table, autoclose?: boolean }?
---@param enter boolean? defaults to true
function M.new_win(mode, buf, config, enter)
    if enter == nil then
        enter = true
    end
    config = config or {}
    local win_opts = {
        number = false,
        relativenumber = false,
        list = false,
        winfixbuf = true,
        winfixwidth = true,
        winfixheight = true,
        wrap = false,
    }

    local win

    if mode == "float" then
        win = api.nvim_open_win(buf, enter, config.win_config or {})
        if config.autoclose then
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
        end
    else
        local last_win = api.nvim_get_current_win()
        vim.cmd(mode .. " +buffer" .. buf)
        win = api.nvim_get_current_win()
        if not enter then
            api.nvim_set_current_win(last_win)
        end
        api.nvim_win_set_config(win, config.win_config or {})
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
---@param column integer 1-based character column
function M.color_char(buf, higroup, line, lnum, column)
    local start_byte = vim.str_byteindex(line, "utf-16", column - 1) + 1
    local end_byte = vim.str_byteindex(line, "utf-16", column)
    vim.hl.range(buf, api.nvim_create_namespace("atone"), higroup, { lnum - 1, start_byte - 1 }, { lnum - 1, end_byte - 1 })
end

---@param color integer
---@param amount number
---@return integer
function M.lighten(color, amount)
    local r = math.floor(color / 0x10000) % 0x100
    local g = math.floor(color / 0x100) % 0x100
    local b = color % 0x100

    r = math.floor(r + (0xFF - r) * amount)
    g = math.floor(g + (0xFF - g) * amount)
    b = math.floor(b + (0xFF - b) * amount)

    return r * 0x10000 + g * 0x100 + b
end

---@param color integer
---@param amount number
---@return integer
function M.darken(color, amount)
    local r = math.floor(color / 0x10000) % 0x100
    local g = math.floor(color / 0x100) % 0x100
    local b = color % 0x100

    r = math.floor(r * (1 - amount))
    g = math.floor(g * (1 - amount))
    b = math.floor(b * (1 - amount))

    return r * 0x10000 + g * 0x100 + b
end

--- Return the UTF-16 code-unit index of the character that contains byte_pos.
--- Corrects for the case where str_utfindex points to the *next* character
--- when byte_pos falls in the middle of a multi-byte sequence.
---@param text string
---@param byte_pos integer 0-based byte index (caller guarantees 0 < byte_pos < #text)
---@return integer UTF-16 code-unit index
local function char_utf16_idx(text, byte_pos)
    local idx = vim.str_utfindex(text, "utf-16", byte_pos)
    -- If the byte start of `idx` is already past byte_pos, we overshot by one.
    if vim.str_byteindex(text, "utf-16", idx) > byte_pos then
        idx = idx - 1
    end
    return idx
end

--- Snap a 0-based byte position to the start of the UTF-8 character that contains it.
--- Input and output are both 0-based byte positions.
---@param text string
---@param byte_pos integer 0-based byte index
---@return integer
function M.char_byte_start(text, byte_pos)
    if byte_pos <= 0 then
        return 0
    end
    if byte_pos >= #text then
        return #text
    end
    return vim.str_byteindex(text, "utf-16", char_utf16_idx(text, byte_pos))
end

--- Snap a 0-based byte position to the exclusive end of the UTF-8 character
--- that contains it.  Input and output are both 0-based byte positions.
---@param text string
---@param byte_pos integer 0-based byte index
---@return integer
function M.char_byte_end(text, byte_pos)
    if byte_pos < 0 then
        return 0
    end
    if byte_pos >= #text then
        return #text
    end
    return vim.str_byteindex(text, "utf-16", char_utf16_idx(text, byte_pos) + 1)
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

---@param win integer
---@return boolean
function M.win_exists(win)
    return win and api.nvim_win_is_valid(win)
end

---@param buf integer
---@return string
function M.buf_filepath(buf)
    return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
end

return M
