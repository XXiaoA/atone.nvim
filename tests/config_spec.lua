---@diagnostic disable: undefined-global, undefined-field
local eq = assert.are.same
local config = require("atone.config")

local saved_env = {
    KITTY_PID = vim.env.KITTY_PID,
    WEZTERM_PANE = vim.env.WEZTERM_PANE,
    TERM_PROGRAM = vim.env.TERM_PROGRAM,
    GHOSTTY_RESOURCES_DIR = vim.env.GHOSTTY_RESOURCES_DIR,
    TERM = vim.env.TERM,
}

local function clear_terminal_env()
    vim.env.KITTY_PID = nil
    vim.env.WEZTERM_PANE = nil
    vim.env.TERM_PROGRAM = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.env.TERM = "xterm-256color"
end

local function restore_terminal_env()
    vim.env.KITTY_PID = saved_env.KITTY_PID
    vim.env.WEZTERM_PANE = saved_env.WEZTERM_PANE
    vim.env.TERM_PROGRAM = saved_env.TERM_PROGRAM
    vim.env.GHOSTTY_RESOURCES_DIR = saved_env.GHOSTTY_RESOURCES_DIR
    vim.env.TERM = saved_env.TERM
end

describe("branch symbol auto-detection", function()
    after_each(function()
        clear_terminal_env()
    end)

    it("detects kitty via KITTY_PID", function()
        vim.env.KITTY_PID = "123"
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("detects wezterm via TERM_PROGRAM", function()
        vim.env.TERM_PROGRAM = "WezTerm"
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("detects ghostty via TERM_PROGRAM", function()
        vim.env.TERM_PROGRAM = "ghostty"
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("detects ghostty via GHOSTTY_RESOURCES_DIR", function()
        vim.env.GHOSTTY_RESOURCES_DIR = "/usr/share/ghostty"
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("detects kitty via TERM fallback", function()
        vim.env.TERM = "xterm-kitty"
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("falls back to default symbols in plain terminals", function()
        config.merge_config({ ui = { branch_symbols = "auto" } })
        eq(config.get_graph_symbols().node, "●")
    end)

    it("respects an explicit true", function()
        config.merge_config({ ui = { branch_symbols = true } })
        eq(config.get_graph_symbols().node, "")
    end)

    it("respects an explicit false even in a supporting terminal", function()
        vim.env.KITTY_PID = "123"
        config.merge_config({ ui = { branch_symbols = false } })
        eq(config.get_graph_symbols().node, "●")
    end)
end)

-- restore the environment and config so later specs see the pinned baseline
restore_terminal_env()
config.merge_config({ ui = { branch_symbols = false } })
