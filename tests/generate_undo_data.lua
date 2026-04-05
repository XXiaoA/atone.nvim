--[[
This script generates a file with random content and a corresponding undo file
with a complex, branching history for testing purposes.

It simulates a user making a series of changes, occasionally undoing to a
random previous state before making more changes.

== Usage ==
nvim --headless -l tests/generate_undo_data.lua [num_nodes] [undo_chance] [output_file] [undo_file]

== Parameters ==
[num_nodes]   (number, optional, default: 10)
The total number of undo nodes (changes) to generate.

[undo_chance] (float, optional, default: 0.1)
The probability (between 0.0 and 1.0) of performing a random undo
before making a new change. A value of 0.3 means a 30% chance.

[output_file] (string, optional, default: "tests/random_file.txt")
The path to save the final text file.

[undo_file]   (string, optional, default: "tests/random_file.undo")
The path to save the generated undo history file.

== Examples ==
-- Generate a simple history with 20 nodes
nvim --headless -l tests/generate_undo_data.lua 20

-- Generate a complex history with 100 nodes and a 50% chance of branching
nvim --headless -l tests/generate_undo_data.lua 100 0.5 tests/my_file.txt tests/my_file.undo

== How to Use for Testing ==
1. Run the script to generate the files.
   nvim --headless -l tests/generate_undo_data.lua 100

2. Open the generated text file in Neovim.
   nvim tests/random_file.txt

3. Load the generated undo history.
   :rundo tests/random_file.undo

4. Use your undo-tree plugin to view the history. It should be branched.
--]]
local arg = arg
local num_nodes = tonumber(arg and arg[1]) or 10
local undo_chance = tonumber(arg and arg[2]) or 0.1
local output_file = (arg and arg[3]) or "tests/random_file.txt"
local undo_file = (arg and arg[4]) or "tests/random_file.undo"

print("Generating test data...")
print("  Number of undo nodes: " .. num_nodes)
print("  Undo chance: " .. undo_chance)
print("  Output file: " .. output_file)
print("  Undo file: " .. undo_file)

local api = vim.api

-- Generates a random line of text.
-- @return string
local function random_line()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
    local len = math.random(20, 60)
    local line = {}
    for _ = 1, len do
        table.insert(line, chars:sub(math.random(1, #chars), math.random(1, #chars)))
    end
    return table.concat(line)
end

-- 1. Create a temporary buffer
local buf = api.nvim_create_buf(false, true)
vim.bo[buf].undolevels = num_nodes + 10 -- Ensure we can store enough undo history
vim.bo[buf].swapfile = false

-- 2. Generate undo history within the buffer's context
api.nvim_buf_call(buf, function()
    -- Create the initial state
    api.nvim_buf_set_lines(buf, 0, -1, false, { "--- Initial Content ---" })

    for i = 1, num_nodes do
        if i > 1 and math.random() < undo_chance then
            local target_seq = math.random(0, i - 1)
            vim.cmd("silent undo " .. target_seq)
        end

        local line_count = api.nvim_buf_line_count(buf)
        if line_count == 0 then
            -- If buffer is empty, just append a new line
            api.nvim_buf_set_lines(buf, 0, 0, false, { string.format("Append %d: %s", i, random_line()) })
        else
            -- Otherwise, randomly choose an action
            local change_type = math.random(1, 3)
            local random_line_num = math.random(0, line_count - 1)

            if line_count < 5 or change_type == 1 then
                -- Append
                api.nvim_buf_set_lines(
                    buf,
                    line_count,
                    line_count,
                    false,
                    { string.format("Append %d: %s", i, random_line()) }
                )
            elseif change_type == 2 then
                -- Modify
                local new_line = string.format("Modify %d: %s", i, random_line())
                api.nvim_buf_set_lines(buf, random_line_num, random_line_num + 1, false, { new_line })
            else
                -- Delete
                if line_count > 1 then
                    api.nvim_buf_set_lines(buf, random_line_num, random_line_num + 1, false, {})
                else
                    -- Can't delete the last line, so append instead
                    api.nvim_buf_set_lines(
                        buf,
                        line_count,
                        line_count,
                        false,
                        { string.format("Append (forced) %d: %s", i, random_line()) }
                    )
                end
            end
        end

        -- Force an undo break. This is a workaround to prevent Neovim
        -- from squashing fast, programmatic changes into a single undo state.
        vim.o.undolevels = vim.o.undolevels
    end

    -- 3. Save the final content to the output file
    local final_content = api.nvim_buf_get_lines(buf, 0, -1, false)
    local file = io.open(output_file, "w")
    if file then
        file:write(table.concat(final_content, "\n"))
        file:close()
        print("Successfully generated file: " .. output_file)
    else
        print("Error: Could not open output file for writing: " .. output_file)
        vim.cmd("qa!")
        return
    end

    -- 4. Write the undo history to the undo file
    vim.cmd("silent wundo! " .. undo_file)
    print("Successfully generated undo file: " .. undo_file)
end)

-- 5. Clean up the buffer we created
api.nvim_buf_delete(buf, { force = true })

print("Done.")

-- Quit Neovim when run from the command line
vim.cmd("qa!")
