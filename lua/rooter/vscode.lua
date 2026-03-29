--- rooter.vscode — VS Code configuration file collection and merging.
--- Reads .vscode/settings.json, launch.json, tasks.json from workspace folders.
--- Handles multi-root workspaces: configs from all folders are merged.
---
---@class rooter.vscode
local M = {}

local parser = require("rooter.parser")
local interpolate = require("rooter.interpolate")
local workspace = require("rooter.workspace")
local root_mod = require("rooter.root")

--- Collect config file paths from all workspace folders + project root.
--- Each folder's .vscode/{config_name} is included, deduplicated.
---@param config_name string e.g., "settings.json", "launch.json", "tasks.json"
---@param path? string file path for context (defaults to current buffer)
---@return { path: string, folder: string }[] configs_to_load
---@return table|nil workspace_data
---@return string|nil ws_root
local function collect_configs(config_name, path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then path = vim.fn.getcwd() end
  path = vim.fn.fnamemodify(path, ":p")

  local effective_root = root_mod.root(path)
  local workspace_data, ws_root, folders = workspace.resolve(path)

  -- Fallback: if no project root, try .vscode directory (for fixtures, standalone configs)
  if not effective_root then
    local search_dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    effective_root = workspace.find_vscode_root(search_dir)
  end

  local configs = {}
  local added = {}

  local function add(config_path, folder_path)
    if not added[config_path] then
      added[config_path] = true
      configs[#configs + 1] = { path = config_path, folder = folder_path }
    end
  end

  -- Collect from all workspace folders
  if workspace_data and folders then
    for _, folder in ipairs(folders) do
      if folder.path ~= effective_root then
        add(folder.path .. "/.vscode/" .. config_name, folder.path)
      end
    end
  end

  -- Add effective root last (always included, deduplicated)
  if effective_root then
    add(effective_root .. "/.vscode/" .. config_name, effective_root)
  end

  return configs, workspace_data, ws_root
end

--- Merge multiple config files, interpolating variables.
--- Array keys (e.g., "configurations", "tasks") are concatenated across files.
--- Each merged item gets a __folder field with the source folder name.
---@param array_keys string|string[] keys to merge as arrays
---@param config_paths { path: string, folder: string }[]
---@param effective_root? string root directory for interpolation fallback
---@param workspace_data? table parsed workspace data
---@param ws_root? string workspace root directory
---@param folders? { path: string, name: string }[] workspace folders for name lookup
---@return table|nil merged configuration, or nil if empty
local function merge_configs(array_keys, config_paths, effective_root, workspace_data, ws_root, folders)
  if type(array_keys) == "string" then
    array_keys = { array_keys }
  end

  -- Build folder path → name lookup
  local folder_names = {}
  if folders then
    for _, folder in ipairs(folders) do
      folder_names[folder.path] = folder.name
    end
  end

  local merged = {}
  for _, key in ipairs(array_keys) do
    merged[key] = {}
  end

  for _, config_entry in ipairs(config_paths) do
    local config_folder = config_entry.folder
    local folder_name = folder_names[config_folder]
      or (config_folder and vim.fn.fnamemodify(config_folder, ":t"))

    local interp_state = {
      workspace = workspace_data,
      workspace_root_dir = ws_root,
      root_dir = config_folder or effective_root,
    }

    local config = parser.parse_json_file(config_entry.path)
    if config then
      config = interpolate.interpolate_config(config, interp_state)
      for _, key in ipairs(array_keys) do
        if config[key] then
          for _, item in ipairs(config[key]) do
            item.__folder = folder_name
            merged[key][#merged[key] + 1] = item
          end
        end
      end
      if config.version and not merged.version then
        merged.version = config.version
      end
    end
  end

  local has_content = false
  for _, key in ipairs(array_keys) do
    if #merged[key] > 0 then
      has_content = true
    else
      merged[key] = nil
    end
  end

  return has_content and merged or nil
end

--- Load per-folder settings from .vscode/settings.json.
---@param folders { path: string, name: string }[]
---@return table<string, table> folder_name → settings
function M.load_folder_settings(folders)
  local folder_settings = {}
  for _, folder in ipairs(folders) do
    local settings = parser.parse_json_file(folder.path .. "/.vscode/settings.json")
    if settings then
      folder_settings[folder.name] = settings
    end
  end
  return folder_settings
end

-- ── Public API ─────────────────────────────────────────────────────────

--- Get workspace/folder settings.
---@param path? string file path for context
---@return table|nil settings from .code-workspace + .vscode/settings.json
function M.settings(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then path = vim.fn.getcwd() end
  path = vim.fn.fnamemodify(path, ":p")

  local workspace_data, ws_root, folders = workspace.resolve(path)
  local settings = workspace_data and workspace_data.settings or nil

  -- Also check .vscode/settings.json at project root
  local project_root = root_mod.root(path)
  if project_root then
    local root_settings = parser.parse_json_file(project_root .. "/.vscode/settings.json")
    if root_settings then
      settings = settings and vim.tbl_deep_extend("force", settings, root_settings) or root_settings
    end
  end

  return settings
end

--- Get merged launch configurations from all workspace folders.
---@param path? string file path for context
---@return table|nil { configurations: table[], compounds: table[] }
function M.launch_configs(path)
  local effective_root = root_mod.root(path)
  if not effective_root and path then
    local search_dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    effective_root = workspace.find_vscode_root(search_dir)
  end
  local config_paths, workspace_data, ws_root = collect_configs("launch.json", path)
  local _, _, folders = workspace.resolve(path)
  local merged = merge_configs(
    { "configurations", "compounds" },
    config_paths, effective_root, workspace_data, ws_root, folders
  )

  -- Also merge launch section from the .code-workspace file itself
  if workspace_data and workspace_data.launch then
    local ws_launch = workspace_data.launch
    if ws_launch.compounds then
      merged = merged or { configurations = {}, compounds = {} }
      merged.compounds = merged.compounds or {}
      for _, compound in ipairs(ws_launch.compounds) do
        compound.__folder = "workspace"
        merged.compounds[#merged.compounds + 1] = compound
      end
    end
    if ws_launch.configurations then
      merged = merged or { configurations = {}, compounds = {} }
      merged.configurations = merged.configurations or {}
      for _, config in ipairs(ws_launch.configurations) do
        config.__folder = "workspace"
        merged.configurations[#merged.configurations + 1] = config
      end
    end
  end

  return merged
end

--- Get merged task configurations from all workspace folders.
---@param path? string file path for context
---@return table|nil { tasks: table[] }
function M.task_configs(path)
  local effective_root = root_mod.root(path)
  if not effective_root and path then
    local search_dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
    effective_root = workspace.find_vscode_root(search_dir)
  end
  local config_paths, workspace_data, ws_root = collect_configs("tasks.json", path)
  local _, _, folders = workspace.resolve(path)
  return merge_configs("tasks", config_paths, effective_root, workspace_data, ws_root, folders)
end

return M
