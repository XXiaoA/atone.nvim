vim.api.nvim_create_user_command("Atone", function(opt)
    require("atone").command(opt)
end, {
    nargs = "+",
    complete = function(ArgLead, CmdLine, _)
        return require("atone").command_complete(ArgLead, CmdLine)
    end,
    bang = true,
})

-- setup automatically
require('atone').setup()
