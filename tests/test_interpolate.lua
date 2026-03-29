local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local interpolate = require("rooter.interpolate")

local T = MiniTest.new_set()

local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local fixtures = vim.fn.fnamemodify(test_dir .. "/fixtures", ":p"):gsub("/$", "")

-- Helper: build a minimal state object for interpolation
local function make_state(root_dir, workspace_data)
  return {
    root_dir = root_dir or fixtures .. "/simple",
    workspace = workspace_data,
    workspace_root_dir = root_dir,
  }
end

-- ── interpolate_string ─────────────────────────────────────────────────

T["interpolate_string"] = MiniTest.new_set()

T["interpolate_string"]["returns non-string input unchanged"] = function()
  eq(interpolate.interpolate_string(nil, make_state()), nil)
  eq(interpolate.interpolate_string(42, make_state()), 42)
end

T["interpolate_string"]["returns string without variables unchanged"] = function()
  eq(interpolate.interpolate_string("hello world", make_state()), "hello world")
end

T["interpolate_string"]["expands ${workspaceFolder}"] = function()
  local state = make_state(fixtures .. "/simple")
  local result = interpolate.interpolate_string("${workspaceFolder}/src", state)
  eq(result, fixtures .. "/simple/src")
end

T["interpolate_string"]["expands ${workspaceFolderBasename}"] = function()
  local state = make_state(fixtures .. "/simple")
  local result = interpolate.interpolate_string("${workspaceFolderBasename}", state)
  eq(result, "simple")
end

T["interpolate_string"]["expands ${env:HOME}"] = function()
  local state = make_state()
  local result = interpolate.interpolate_string("${env:HOME}", state)
  eq(result, os.getenv("HOME") or "")
end

T["interpolate_string"]["expands ${env:USER}"] = function()
  local state = make_state()
  local result = interpolate.interpolate_string("${env:USER}", state)
  eq(result, os.getenv("USER") or "")
end

T["interpolate_string"]["returns empty for unknown env var"] = function()
  local state = make_state()
  local result = interpolate.interpolate_string("${env:ROOTER_TEST_NONEXISTENT_VAR}", state)
  eq(result, "")
end

T["interpolate_string"]["expands ${config:key} from workspace settings"] = function()
  local state = make_state(fixtures .. "/workspace", {
    settings = { editor = { tabSize = 4 } },
  })
  local result = interpolate.interpolate_string("${config:editor.tabSize}", state)
  eq(result, "4")
end

T["interpolate_string"]["expands ${pathSeparator}"] = function()
  local state = make_state()
  local result = interpolate.interpolate_string("${pathSeparator}", state)
  eq(result, "/")
end

T["interpolate_string"]["expands ${lua:expression}"] = function()
  local state = make_state()
  local result = interpolate.interpolate_string("${lua:1+1}", state)
  eq(result, "2")
end

T["interpolate_string"]["expands ${workspaceFolder:N} for indexed folders"] = function()
  local state = make_state(fixtures .. "/workspace", {
    folders = {
      { path = "frontend" },
      { path = "backend" },
    },
  })
  local result1 = interpolate.interpolate_string("${workspaceFolder:1}", state)
  local result2 = interpolate.interpolate_string("${workspaceFolder:2}", state)
  -- Folders are resolved relative to workspace_root_dir
  eq(result1:match("frontend$") ~= nil, true)
  eq(result2:match("backend$") ~= nil, true)
end

-- ── interpolate_config ─────────────────────────────────────────────────

T["interpolate_config"] = MiniTest.new_set()

T["interpolate_config"]["recursively interpolates nested tables"] = function()
  local state = make_state(fixtures .. "/simple")
  local input = {
    program = "${workspaceFolder}/src/index.ts",
    args = { "--config", "${workspaceFolder}/config.json" },
    nested = {
      cwd = "${workspaceFolder}",
    },
  }
  local result = interpolate.interpolate_config(input, state)
  eq(result.program, fixtures .. "/simple/src/index.ts")
  eq(result.args[2], fixtures .. "/simple/config.json")
  eq(result.nested.cwd, fixtures .. "/simple")
end

T["interpolate_config"]["preserves non-string values"] = function()
  local state = make_state()
  local input = { count = 42, enabled = true, name = "test" }
  local result = interpolate.interpolate_config(input, state)
  eq(result.count, 42)
  eq(result.enabled, true)
  eq(result.name, "test")
end

return T
