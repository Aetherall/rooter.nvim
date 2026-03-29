--- rooter.root — Project root detection.
--- Uses vim.fs.root() to walk up from a path looking for project markers.
--- Returns nil for non-project directories (~, /, /tmp).
---
---@class rooter.root
local M = {}

--- Project markers. Directories or files that indicate a project root.
---@type string[]
M.markers = {
  ".git",
  "flake.nix",
  "package.json",
  "Cargo.toml",
  "go.mod",
  "pyproject.toml",
  "Makefile",
}

--- Directories that are never project roots.
---@type string[]
M.exclude = {
  vim.fn.resolve(vim.fn.expand("~")),
  "/",
  "/tmp",
}

--- Apply configuration.
---@param opts? { markers?: string[], exclude?: string[] }
function M.configure(opts)
  if not opts then return end
  if opts.markers then M.markers = opts.markers end
  if opts.exclude then M.exclude = opts.exclude end
end

--- Check if a directory has project markers.
--- Returns false for excluded directories.
---@param dir string absolute directory path
---@return boolean
function M.is_project(dir)
  if not dir or dir == "" then return false end
  dir = vim.fn.resolve(dir)
  for _, excluded in ipairs(M.exclude) do
    if dir == excluded then return false end
  end
  for _, marker in ipairs(M.markers) do
    local path = dir .. "/" .. marker
    if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
      return true
    end
  end
  return false
end

--- Find the project root for a given path or the current context.
---
--- Resolution order:
---   1. vim.fn.getcwd() — if it's a project (respects :tcd from project switcher)
---   2. vim.fs.root(path, markers) — walk up from the path
---   3. nil — not in a project
---
---@param path? string file path or directory to resolve from.
---       If nil, uses the current buffer's file path.
---@return string|nil root absolute path to project root, or nil
function M.root(path)
  -- Resolve path from argument or buffer
  if not path or path == "" then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname ~= "" and not bufname:match("^%w+://") then
      path = bufname
    end
  end

  -- Priority 1: walk up from path (finds the nearest root)
  if path then
    local found = vim.fs.root(path, M.markers)
    if found then
      found = vim.fn.resolve(found)
      for _, excluded in ipairs(M.exclude) do
        if found == excluded then return nil end
      end
      return found
    end
    -- Path was given but no markers found — don't fall back to cwd
    return nil
  end

  -- Priority 2: cwd if it's a project (handles project switch via :tcd
  -- when no buffer is open in the new project yet)
  local cwd = vim.fn.resolve(vim.fn.getcwd())
  if M.is_project(cwd) then
    return cwd
  end

  return nil
end

--- Get the project name (last path segment of the root).
---@param path? string file path to resolve from
---@return string|nil name
function M.name(path)
  local root = M.root(path)
  if not root then return nil end
  return vim.fn.fnamemodify(root, ":t")
end

--- Check if the project has a specific file or directory.
--- Accepts a string or a list of strings (checked in order, first match wins).
--- Searches from the project root, not the cwd.
---@param markers string|string[] file/directory name(s) to check, ordered by priority
---@param path? string file path to resolve the project from
---@return string|nil absolute path to the first marker found, or nil
function M.has(markers, path)
  local root = M.root(path)
  if not root then return nil end
  if type(markers) == "string" then markers = { markers } end
  for _, marker in ipairs(markers) do
    local full = root .. "/" .. marker
    if vim.fn.filereadable(full) == 1 or vim.fn.isdirectory(full) == 1 then
      return full
    end
  end
  return nil
end

return M
