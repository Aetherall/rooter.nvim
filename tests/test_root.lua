local MiniTest = require("mini.test")
local expect, eq, neq = MiniTest.expect, MiniTest.expect.equality, MiniTest.expect.no_equality
local root_mod = require("rooter.root")

local T = MiniTest.new_set()

-- Resolve fixtures path (absolute)
local test_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local fixtures = vim.fn.fnamemodify(test_dir .. "/fixtures", ":p"):gsub("/$", "")

-- ── root() ─────────────────────────────────────────────────────────────

T["root()"] = MiniTest.new_set()

T["root()"]["finds .git root from nested file"] = function()
  local r = root_mod.root(fixtures .. "/simple/src/main.lua")
  eq(r, fixtures .. "/simple")
end

T["root()"]["finds .git root from directory"] = function()
  local r = root_mod.root(fixtures .. "/simple/src")
  eq(r, fixtures .. "/simple")
end

T["root()"]["finds .git root at the root itself"] = function()
  local r = root_mod.root(fixtures .. "/simple")
  eq(r, fixtures .. "/simple")
end

T["root()"]["finds monorepo root (nearest .git, not package.json)"] = function()
  local r = root_mod.root(fixtures .. "/monorepo/packages/app/src/index.ts")
  eq(r, fixtures .. "/monorepo")
end

T["root()"]["returns nil for excluded dirs"] = function()
  local r = root_mod.root(vim.fn.expand("~"))
  eq(r, nil)
end

T["root()"]["returns nil for filesystem root"] = function()
  local r = root_mod.root("/")
  eq(r, nil)
end

T["root()"]["returns nil when no markers found"] = function()
  -- Use /tmp which is excluded and has no markers above it
  local tmpfile = "/tmp/rooter_test_no_markers.txt"
  vim.fn.writefile({}, tmpfile)
  local r = root_mod.root(tmpfile)
  vim.fn.delete(tmpfile)
  eq(r, nil)
end

T["root()"]["returns nil for nil input"] = function()
  -- When no buffer and no cwd match
  local old_cwd = vim.fn.getcwd()
  vim.cmd("tcd /tmp")
  local r = root_mod.root()
  vim.cmd("tcd " .. old_cwd)
  eq(r, nil)
end

T["root()"]["prefers cwd when it is a project"] = function()
  local old_cwd = vim.fn.getcwd()
  vim.cmd("tcd " .. fixtures .. "/simple")
  local r = root_mod.root()
  vim.cmd("tcd " .. old_cwd)
  eq(r, fixtures .. "/simple")
end

T["root()"]["uses buffer path when cwd is not a project"] = function()
  local old_cwd = vim.fn.getcwd()
  vim.cmd("tcd /tmp")
  local r = root_mod.root(fixtures .. "/simple/src/main.lua")
  vim.cmd("tcd " .. old_cwd)
  eq(r, fixtures .. "/simple")
end

-- ── is_project() ───────────────────────────────────────────────────────

T["is_project()"] = MiniTest.new_set()

T["is_project()"]["true for dir with .git"] = function()
  eq(root_mod.is_project(fixtures .. "/simple"), true)
end

T["is_project()"]["true for dir with package.json"] = function()
  eq(root_mod.is_project(fixtures .. "/monorepo/packages/app"), true)
end

T["is_project()"]["false for dir without markers"] = function()
  eq(root_mod.is_project(fixtures .. "/empty"), false)
end

T["is_project()"]["false for home dir"] = function()
  eq(root_mod.is_project(vim.fn.expand("~")), false)
end

T["is_project()"]["false for /tmp"] = function()
  eq(root_mod.is_project("/tmp"), false)
end

T["is_project()"]["false for /"] = function()
  eq(root_mod.is_project("/"), false)
end

-- ── name() ─────────────────────────────────────────────────────────────

T["name()"] = MiniTest.new_set()

T["name()"]["returns last segment of root"] = function()
  local n = root_mod.name(fixtures .. "/simple/src/main.lua")
  eq(n, "simple")
end

T["name()"]["returns nil when no project"] = function()
  local n = root_mod.name("/tmp/no_project_here.txt")
  eq(n, nil)
end

-- ── has() ──────────────────────────────────────────────────────────────

T["has()"] = MiniTest.new_set()

T["has()"]["finds file in project root"] = function()
  local result = root_mod.has("src/main.lua", fixtures .. "/simple/src/main.lua")
  neq(result, nil)
  eq(result:match("simple/src/main.lua$") ~= nil, true)
end

T["has()"]["returns nil when file not found"] = function()
  local result = root_mod.has("nonexistent.txt", fixtures .. "/simple/src/main.lua")
  eq(result, nil)
end

T["has()"]["finds directory in project root"] = function()
  local result = root_mod.has("src", fixtures .. "/simple/src/main.lua")
  neq(result, nil)
  eq(result:match("simple/src$") ~= nil, true)
end

T["has()"]["accepts table, returns first match by priority"] = function()
  -- .git exists, flake.nix doesn't in simple/
  local result = root_mod.has({ "flake.nix", ".git" }, fixtures .. "/simple/src/main.lua")
  neq(result, nil)
  eq(result:match("%.git$") ~= nil, true)
end

T["has()"]["priority: returns first match, not all"] = function()
  -- packages/app has package.json, create a second marker scenario
  local result = root_mod.has({ "package.json", ".git" }, fixtures .. "/monorepo/packages/app/src/index.ts")
  neq(result, nil)
  -- monorepo root has .git but packages/app has package.json
  -- root is monorepo/ (nearest .git), so package.json is at monorepo root level?
  -- Actually monorepo/ has .git but NOT package.json at root.
  -- So this should find .git
  eq(result:match("%.git$") ~= nil, true)
end

T["has()"]["returns nil when not in a project"] = function()
  local result = root_mod.has("anything", "/tmp/no_project.txt")
  eq(result, nil)
end

-- ── configure() ────────────────────────────────────────────────────────

T["configure()"] = MiniTest.new_set()

T["configure()"]["custom markers"] = function()
  local old_markers = vim.deepcopy(root_mod.markers)
  root_mod.configure({ markers = { "package.json" } })
  -- Now package.json is a marker but .git is not
  local r = root_mod.root(fixtures .. "/monorepo/packages/app/src/index.ts")
  eq(r, fixtures .. "/monorepo/packages/app")
  -- Restore
  root_mod.configure({ markers = old_markers })
end

T["configure()"]["custom exclusions"] = function()
  local old_exclude = vim.deepcopy(root_mod.exclude)
  root_mod.configure({ exclude = { fixtures .. "/simple" } })
  local r = root_mod.root(fixtures .. "/simple/src/main.lua")
  eq(r, nil)
  -- Restore
  root_mod.configure({ exclude = old_exclude })
end

return T
