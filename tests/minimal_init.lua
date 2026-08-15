local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"

if not vim.loop.fs_stat(plenary_path) then
    vim.fn.system({
        "git",
        "clone",
        "--depth=1",
        "https://github.com/nvim-lua/plenary.nvim",
        plenary_path,
    })
end

vim.opt.rtp:prepend(".")
vim.opt.rtp:prepend(plenary_path)

-- Disable branch symbol auto-detection so tests are independent of the host
-- terminal (a kitty/wezterm/ghostty environment would otherwise flip the
-- default-symbol assertions). Tests that need branch symbols opt in explicitly.
require("atone").setup({ ui = { branch_symbols = false } })
