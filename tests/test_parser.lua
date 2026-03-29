local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local parser = require("rooter.parser")

local T = MiniTest.new_set()

local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local fixtures = vim.fn.fnamemodify(test_dir .. "/fixtures", ":p"):gsub("/$", "")

-- ── parse_json_file ────────────────────────────────────────────────────

T["parse_json_file"] = MiniTest.new_set()

T["parse_json_file"]["parses valid JSON"] = function()
  local data = parser.parse_json_file(fixtures .. "/monorepo/packages/app/package.json")
  eq(type(data), "table")
  eq(data.name, "app")
end

T["parse_json_file"]["strips // comments"] = function()
  local data = parser.parse_json_file(fixtures .. "/vscode/.vscode/settings.json")
  eq(type(data), "table")
  eq(data["editor.tabSize"], 2)
  eq(data["typescript.tsdk"], "node_modules/typescript/lib")
end

T["parse_json_file"]["strips trailing commas"] = function()
  local data = parser.parse_json_file(fixtures .. "/vscode/.vscode/launch.json")
  eq(type(data), "table")
  eq(data.version, "0.2.0")
  eq(#data.configurations, 1)
  eq(data.configurations[1].name, "Launch Program")
end

T["parse_json_file"]["returns nil for missing file"] = function()
  local data = parser.parse_json_file("/nonexistent/file.json")
  eq(data, nil)
end

T["parse_json_file"]["returns nil for invalid JSON"] = function()
  local tmpfile = "/tmp/rooter_test_invalid.json"
  vim.fn.writefile({ "this is not json {{{" }, tmpfile)
  local data = parser.parse_json_file(tmpfile)
  vim.fn.delete(tmpfile)
  eq(data, nil)
end

-- ── parse_workspace_file ───────────────────────────────────────────────

T["parse_workspace_file"] = MiniTest.new_set()

T["parse_workspace_file"]["parses .code-workspace"] = function()
  local data = parser.parse_workspace_file(fixtures .. "/workspace/project.code-workspace")
  eq(type(data), "table")
  eq(#data.folders, 2)
  eq(data.folders[1].path, "frontend")
  eq(data.folders[1].name, "Frontend")
  eq(data.folders[2].path, "backend")
  eq(data.folders[2].name, "Backend")
  eq(data.settings["editor.tabSize"], 2)
end

return T
