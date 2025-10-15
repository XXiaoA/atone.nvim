local api = vim.api
local config = require("atone.config")
local core = require("atone.core")
local M = {}

local highlights = {
    ID = { link = "Number" },
    CurrentNode = { link = "Keyword" },
    IDBracket = { link = "Comment" },
}

local function set_highlights()
    for suffix, hi_value in pairs(highlights) do
        local hi_name = "Atone" .. suffix
        if vim.tbl_isempty(api.nvim_get_hl(0, { name = hi_name })) then
            api.nvim_set_hl(0, hi_name, hi_value)
        end
    end
end

---@class AtoneCmdSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback, taking the lead of the subcommand's arguments

---@type table<string, AtoneCmdSubcommand>
local subcommand_tbl = {
    toggle = {
        impl = core.toggle,
    },
    open = {
        impl = core.open,
    },
    close = {
        impl = core.close,
    },
    focus = {
        impl = core.focus,
    },
}
---@param opts table :h lua-guide-commands-create
local function atone_cmd(opts)
    local fargs = opts.fargs
    local subcommand_key = fargs[1] or "open"
    -- Get the subcommand's arguments, if any
    local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand then
        vim.notify("Atone: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
        return
    end
    -- Invoke the subcommand
    subcommand.impl(args, opts)
end

function M.setup(user_opts)
    user_opts = user_opts or {}
    config.merge_config(user_opts)

    api.nvim_create_user_command("Atone", atone_cmd, {
        nargs = "*",
        complete = function(arg_lead, cmdline, _)
            -- Get the subcommand.
            local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Atone[!]*%s(%S+)%s(.*)$")
            if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
                -- The subcommand has completions. Return them.
                return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
            end
            -- Check if cmdline is a subcommand
            if cmdline:match("^['<,'>]*Atone[!]*%s+%w*$") then
                -- Filter subcommands that match
                local subcommand_keys = vim.tbl_keys(subcommand_tbl)
                return vim.iter(subcommand_keys)
                    :filter(function(key)
                        return key:find(arg_lead) ~= nil
                    end)
                    :totable()
            end
        end,
        bang = true,
    })

    -- lazy load plugin will not trigger ColorScheme event
    -- so need to call set_highlights function in setup
    set_highlights()
    -- register call to ColorScheme event
    -- reset highlights when colorscheme changed
    api.nvim_create_autocmd("ColorScheme", {
        group = core.augroup,
        callback = set_highlights,
    })
    api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
        group = core.augroup,
        callback = function(ctx)
            if core._show and ctx.buf == core.attach_buf then
                core.refresh()
            end
        end,
    })
    if config.opts.auto_attach.enabled then
        api.nvim_create_autocmd("BufEnter", {
            group = core.augroup,
            callback = function(ctx)
                vim.schedule(function()
                    if
                        api.nvim_buf_is_valid(ctx.buf)
                        and core._show
                        and ctx.buf ~= core.attach_buf
                        and vim.bo[ctx.buf].bt == ""
                        and not vim.tbl_contains(config.opts.auto_attach.excluded_ft, vim.bo[ctx.buf].ft)
                    then
                        core.attach_buf = ctx.buf
                        core.refresh()
                    end
                end)
            end,
        })
    end
end

return M
