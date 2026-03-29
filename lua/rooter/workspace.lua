--- rooter.workspace — VS Code workspace folder resolution.
--- Finds .code-workspace files, parses them, resolves folder paths,
--- and determines which workspace folder contains a given file.
---
---@class rooter.workspace
local M = {}

local parser = require("rooter.parser")

--- Find .code-workspace file by walking up from a directory.
--- Walks all the way to / regardless of .git or .vscode directories.
---@param start_dir string starting directory (absolute)
---@return string|nil workspace_file absolute path to .code-workspace file
function M.find_workspace_file(start_dir)
  if not start_dir or start_dir:match("^%w+://") then return nil end
  local current = start_dir
  while current ~= "/" do
    local files = vim.fn.globpath(current, "*.code-workspace", false, true)
    if #files > 0 then return files[1] end
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then break end
    current = parent
  end
  return nil
end

--- Find .vscode directory by walking up from a directory.
---@param start_dir string starting directory (absolute)
---@return string|nil parent absolute path of the directory containing .vscode
function M.find_vscode_root(start_dir)
  if not start_dir or start_dir:match("^%w+://") then return nil end
  local current = start_dir
  while current ~= "/" do
    if vim.fn.isdirectory(current .. "/.vscode") == 1 then
      return current
    end
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then break end
    current = parent
  end
  return nil
end

--- Resolve workspace folder paths from parsed workspace data.
--- Converts relative paths to absolute using the workspace root.
---@param workspace_data table parsed .code-workspace data
---@param ws_root string directory containing the .code-workspace file
---@return { path: string, name: string }[] folders
function M.resolve_folders(workspace_data, ws_root)
  local folders = {}
  if not workspace_data or not workspace_data.folders then return folders end
  for _, folder in ipairs(workspace_data.folders) do
    local folder_path = folder.path
    if folder_path == "." then
      folder_path = ws_root
    elseif not vim.startswith(folder_path, "/") then
      folder_path = ws_root .. "/" .. folder_path
    end
    folder_path = vim.fn.resolve(folder_path)
    folders[#folders + 1] = {
      path = folder_path,
      name = folder.name or vim.fn.fnamemodify(folder_path, ":t"),
    }
  end
  return folders
end

--- Resolve full workspace context for a path.
--- Walks up to find .code-workspace, parses it, resolves folders.
---@param path string absolute file or directory path
---@return table|nil workspace_data parsed workspace data
---@return string|nil ws_root workspace root directory
---@return { path: string, name: string }[]|nil folders resolved folder list
function M.resolve(path)
  if not path or path == "" then return nil, nil, nil end
  local search_dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  local workspace_file = M.find_workspace_file(search_dir)
  if not workspace_file then return nil, nil, nil end
  local workspace_data = parser.parse_workspace_file(workspace_file)
  if not workspace_data then return nil, nil, nil end
  local ws_root = vim.fn.fnamemodify(workspace_file, ":h")
  local folders = M.resolve_folders(workspace_data, ws_root)
  return workspace_data, ws_root, folders
end

--- Get all workspace folders for a path.
--- If a .code-workspace file is found, returns its folders.
--- Otherwise returns a single-element list with the project root.
---@param path? string file path (defaults to current buffer)
---@return { path: string, name: string }[] folders
function M.folders(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then path = vim.fn.getcwd() end
  path = vim.fn.fnamemodify(path, ":p")

  local _, _, folders = M.resolve(path)
  if folders and #folders > 0 then return folders end

  -- Fallback: single folder from project root
  local root = require("rooter.root").root(path)
  if root then
    return { { path = root, name = vim.fn.fnamemodify(root, ":t") } }
  end
  return {}
end

--- Find which workspace folder contains a given path.
---@param path? string absolute file path (defaults to current buffer)
---@return string|nil folder_path absolute path of the containing folder
function M.folder_for(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then return nil end
  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")

  local _, _, folders = M.resolve(path)
  if folders then
    for _, folder in ipairs(folders) do
      if path:find(folder.path .. "/", 1, true) == 1 or path == folder.path then
        return folder.path
      end
    end
  end

  -- Fallback: project root
  return require("rooter.root").root(path)
end

return M
