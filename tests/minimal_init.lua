-- Minimal init for running tests with mini.test
-- Usage: nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"

-- Add rooter.nvim to runtimepath
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(root)

-- Add mini.nvim to runtimepath
local mini_path = root .. "/deps/mini.nvim"
vim.opt.rtp:prepend(mini_path)

-- Set up mini.test
require("mini.test").setup()
