local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local workspace = require("rooter.workspace")

local T = MiniTest.new_set()

local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local fixtures = vim.fn.fnamemodify(test_dir .. "/fixtures", ":p"):gsub("/$", "")

-- ── find_workspace_file ────────────────────────────────────────────────

T["find_workspace_file"] = MiniTest.new_set()

T["find_workspace_file"]["finds .code-workspace from nested dir"] = function()
  local f = workspace.find_workspace_file(fixtures .. "/workspace/frontend/src")
  eq(f, fixtures .. "/workspace/project.code-workspace")
end

T["find_workspace_file"]["finds .code-workspace from workspace root"] = function()
  local f = workspace.find_workspace_file(fixtures .. "/workspace")
  eq(f, fixtures .. "/workspace/project.code-workspace")
end

T["find_workspace_file"]["returns nil when no workspace file"] = function()
  local f = workspace.find_workspace_file(fixtures .. "/simple/src")
  eq(f, nil)
end

T["find_workspace_file"]["returns nil for URI schemes"] = function()
  local f = workspace.find_workspace_file("dap://some/path")
  eq(f, nil)
end

-- ── find_vscode_root ───────────────────────────────────────────────────

T["find_vscode_root"] = MiniTest.new_set()

T["find_vscode_root"]["finds .vscode parent"] = function()
  local r = workspace.find_vscode_root(fixtures .. "/vscode")
  eq(r, fixtures .. "/vscode")
end

T["find_vscode_root"]["returns nil when no .vscode"] = function()
  local r = workspace.find_vscode_root("/tmp")
  eq(r, nil)
end

-- ── resolve_folders ────────────────────────────────────────────────────

T["resolve_folders"] = MiniTest.new_set()

T["resolve_folders"]["resolves relative paths"] = function()
  local data = { folders = { { path = "frontend", name = "Frontend" }, { path = "backend", name = "Backend" } } }
  local folders = workspace.resolve_folders(data, fixtures .. "/workspace")
  eq(#folders, 2)
  eq(folders[1].name, "Frontend")
  eq(folders[1].path:match("frontend$") ~= nil, true)
  eq(folders[2].name, "Backend")
  eq(folders[2].path:match("backend$") ~= nil, true)
end

T["resolve_folders"]["resolves dot path to ws_root"] = function()
  local data = { folders = { { path = "." } } }
  local folders = workspace.resolve_folders(data, fixtures .. "/workspace")
  eq(#folders, 1)
  eq(folders[1].path, vim.fn.resolve(fixtures .. "/workspace"))
end

T["resolve_folders"]["auto-names from path"] = function()
  local data = { folders = { { path = "frontend" } } }
  local folders = workspace.resolve_folders(data, fixtures .. "/workspace")
  eq(folders[1].name, "frontend")
end

T["resolve_folders"]["returns empty for nil data"] = function()
  eq(#workspace.resolve_folders(nil, "/any"), 0)
  eq(#workspace.resolve_folders({}, "/any"), 0)
end

-- ── resolve ────────────────────────────────────────────────────────────

T["resolve"] = MiniTest.new_set()

T["resolve"]["resolves from file in workspace"] = function()
  local data, ws_root, folders = workspace.resolve(fixtures .. "/workspace/frontend/src/app.ts")
  eq(type(data), "table")
  eq(ws_root, fixtures .. "/workspace")
  eq(#folders, 2)
end

T["resolve"]["returns nil for non-workspace project"] = function()
  local data = workspace.resolve(fixtures .. "/simple/src/main.lua")
  eq(data, nil)
end

-- ── folders ────────────────────────────────────────────────────────────

T["folders"] = MiniTest.new_set()

T["folders"]["returns workspace folders"] = function()
  local f = workspace.folders(fixtures .. "/workspace/frontend/src/app.ts")
  eq(#f, 2)
  eq(f[1].name, "Frontend")
  eq(f[2].name, "Backend")
end

T["folders"]["falls back to single root for non-workspace"] = function()
  local f = workspace.folders(fixtures .. "/simple/src/main.lua")
  eq(#f, 1)
  eq(f[1].name, "simple")
end

-- ── folder_for ─────────────────────────────────────────────────────────

T["folder_for"] = MiniTest.new_set()

T["folder_for"]["finds correct folder for frontend file"] = function()
  local f = workspace.folder_for(fixtures .. "/workspace/frontend/src/app.ts")
  eq(f ~= nil, true)
  eq(f:match("frontend$") ~= nil, true)
end

T["folder_for"]["finds correct folder for backend file"] = function()
  local f = workspace.folder_for(fixtures .. "/workspace/backend/src/server.ts")
  eq(f ~= nil, true)
  eq(f:match("backend$") ~= nil, true)
end

T["folder_for"]["falls back to project root for non-workspace"] = function()
  local f = workspace.folder_for(fixtures .. "/simple/src/main.lua")
  eq(f, fixtures .. "/simple")
end

return T
