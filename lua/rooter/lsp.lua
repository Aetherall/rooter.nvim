--- rooter.lsp — LSP integration for rooter.nvim.
--- Provides root_dir, before_init, and reuse_client for vim.lsp.config('*', ...).
--- Handles multi-root workspaces: lazy folder addition, per-folder settings,
--- workspace/configuration handler.
---
---@class rooter.lsp
local M = {}

local interpolate = require("rooter.interpolate")
local workspace_mod = require("rooter.workspace")
local parser = require("rooter.parser")
local root_mod = require("rooter.root")

-- ── Settings extraction ────────────────────────────────────────────────

--- Convert flat dot-notation settings to nested tables.
--- e.g., "Lua.runtime.version" = "LuaJIT" → {Lua = {runtime = {version = "LuaJIT"}}}
local function unflatten_settings(flat_settings, prefix)
  local result = {}
  for key, value in pairs(flat_settings) do
    if vim.startswith(key, prefix .. ".") then
      local path = key:sub(#prefix + 2)
      local parts = vim.split(path, ".", { plain = true })
      local current = result
      for i = 1, #parts - 1 do
        if not current[parts[i]] then current[parts[i]] = {} end
        current = current[parts[i]]
      end
      current[parts[#parts]] = value
    end
  end
  return result
end

--- Default LSP server name → VS Code setting prefix mapping.
local DEFAULT_PREFIXES = {
  pyright = "python", pylsp = "python", ruff_lsp = "python",
  tsserver = "typescript", ts_ls = "typescript", vtsls = "typescript",
  denols = "deno", rust_analyzer = "rust-analyzer", gopls = "gopls",
  clangd = "clangd", lua_ls = "Lua", emmylua_ls = "Lua",
  eslint = "eslint", jsonls = "json", yamlls = "yaml",
  html = "html", cssls = "css", tailwindcss = "tailwindCSS",
  biome = "biome", nixd = "nix",
}

M._custom_prefixes = {}

--- Register a custom setting prefix for an LSP server.
---@param server_name string e.g., "my_custom_ls"
---@param prefix string e.g., "myCustom"
function M.register_server_settings_prefix(server_name, prefix)
  M._custom_prefixes[server_name] = prefix
end

local function get_prefix(server_name)
  return M._custom_prefixes[server_name]
    or DEFAULT_PREFIXES[server_name]
    or server_name
end

--- Extract settings for a prefix (handles both flat and nested formats).
local function extract_prefix_settings(settings, prefix)
  if settings[prefix] and type(settings[prefix]) == "table" then
    return { [prefix] = vim.deepcopy(settings[prefix]) }
  end
  local nested = unflatten_settings(settings, prefix)
  if next(nested) then
    return { [prefix] = nested }
  end
  return {}
end

--- Load per-folder settings from .vscode/settings.json.
local function load_folder_settings(folders)
  local result = {}
  for _, folder in ipairs(folders) do
    local settings = parser.parse_json_file(folder.path .. "/.vscode/settings.json")
    if settings then result[folder.name] = settings end
  end
  return result
end

--- Build LSP state from workspace context.
local function build_state(workspace_data, ws_root, folders)
  return {
    workspace = workspace_data,
    root_dir = ws_root,
    folder_settings = folders and load_folder_settings(folders) or nil,
  }
end

--- Get LSP settings for a server, optionally scoped to a workspace folder.
---@param state table LSP state from build_state
---@param server_name string LSP server name
---@param folder_name? string workspace folder name for folder-specific overrides
---@return table settings
function M.get_lsp_settings(state, server_name, folder_name)
  if not state.workspace or not state.workspace.settings then return {} end

  local prefix = get_prefix(server_name)
  local result = extract_prefix_settings(state.workspace.settings, prefix)

  -- Direct server settings (e.g., settings["tsserver"] = {...})
  local ws_settings = state.workspace.settings
  if ws_settings[server_name] and type(ws_settings[server_name]) == "table" then
    result[server_name] = vim.deepcopy(ws_settings[server_name])
  end

  -- Merge folder-specific settings
  if folder_name and state.folder_settings and state.folder_settings[folder_name] then
    local fs = state.folder_settings[folder_name]
    local folder_result = extract_prefix_settings(fs, prefix)
    if fs[server_name] and type(fs[server_name]) == "table" then
      folder_result[server_name] = vim.deepcopy(fs[server_name])
    end
    result = vim.tbl_deep_extend("force", result, folder_result)
  end

  return interpolate.interpolate_config(result, state)
end

-- ── LSP root_dir ───────────────────────────────────────────────────────

--- Get the effective project root for LSP.
--- Priority: workspace folder > workspace root > .vscode within .git > .git > nil.
--- Returns nil for non-project directories (prevents LSP from starting).
---@param path string file path
---@return string|nil root
local function get_lsp_root(path)
  if not path or path == "" then return nil end
  local abs_path = vim.fn.fnamemodify(path, ":p")
  local search_dir = vim.fn.isdirectory(abs_path) == 1 and abs_path or vim.fn.fnamemodify(abs_path, ":h")

  -- Try workspace folder first
  local _, ws_root, folders = workspace_mod.resolve(abs_path)
  if folders then
    for _, folder in ipairs(folders) do
      if abs_path:find(folder.path .. "/", 1, true) == 1 or abs_path == folder.path then
        return folder.path
      end
    end
    if ws_root then return ws_root end
  end

  -- .vscode within .git boundary
  local git_root = vim.fs.root(search_dir, { ".git" })
  local vscode_root = workspace_mod.find_vscode_root(search_dir)
  if vscode_root and git_root and vscode_root:find(git_root, 1, true) then
    return vscode_root
  end

  -- .git root
  if git_root then
    for _, excluded in ipairs(root_mod.exclude) do
      if git_root == excluded then return nil end
    end
    return git_root
  end

  return nil
end

-- ── LSP callbacks ──────────────────────────────────────────────────────

--- root_dir callback for vim.lsp.config.
---@param bufnr integer
---@param on_dir fun(root: string)
local function lsp_root_dir(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local root = get_lsp_root(fname)
  if root then on_dir(root) end
  -- nil → on_dir not called → LSP doesn't start (OOM prevention)
end

--- Handle workspace/configuration requests.
local function handle_workspace_configuration(err, result, ctx)
  if err then return {} end
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then return {} end

  local ws_data, ws_root, folders = workspace_mod.resolve(client.root_dir or vim.fn.getcwd())
  local state = build_state(ws_data, ws_root, folders)

  local folder_uri_map = {}
  if folders then
    for _, folder in ipairs(folders) do
      folder_uri_map[vim.uri_from_fname(folder.path)] = folder.name
    end
  end

  local responses = {}
  for _, item in ipairs(result.items or {}) do
    local folder_name = nil
    if item.scopeUri then
      for uri, name in pairs(folder_uri_map) do
        if item.scopeUri == uri or vim.startswith(item.scopeUri, uri .. "/") then
          folder_name = name
          break
        end
      end
    end

    local settings = client.name and M.get_lsp_settings(state, client.name, folder_name) or {}
    if item.section and settings[item.section] then
      responses[#responses + 1] = settings[item.section]
    else
      responses[#responses + 1] = settings
    end
  end
  return responses
end

--- before_init callback for vim.lsp.config.
local function lsp_before_init(params, config)
  local root = type(config.root_dir) == "string" and config.root_dir or vim.fn.getcwd()
  local ws_data, ws_root, folders = workspace_mod.resolve(root)
  local state = build_state(ws_data, ws_root, folders)

  -- Inject settings if not already set
  if not config.settings or vim.tbl_isempty(config.settings) then
    if config.name then
      config.settings = M.get_lsp_settings(state, config.name)
    end
  end

  -- Inject only the containing workspace folder (not all — prevents eager loading)
  if ws_data and folders and not config.workspace_folders then
    local abs_root = vim.fn.fnamemodify(root, ":p")
    for _, folder in ipairs(folders) do
      if abs_root:find(folder.path .. "/", 1, true) == 1 or abs_root == folder.path then
        config.workspace_folders = {
          { uri = vim.uri_from_fname(folder.path), name = folder.name },
        }
        break
      end
    end
  end

  -- Set up workspace/configuration handler
  config.handlers = config.handlers or {}
  if not config.handlers["workspace/configuration"] then
    config.handlers["workspace/configuration"] = handle_workspace_configuration
  end
end

--- reuse_client callback: reuse clients within the same workspace.
--- Lazily adds new folders via workspace/didChangeWorkspaceFolders.
local function lsp_reuse_client(client, config)
  if client.name ~= config.name or client:is_stopped() then return false end

  local new_root = config.root_dir
  if type(new_root) ~= "string" or new_root == "" then return false end

  local _, new_ws_root = workspace_mod.resolve(new_root)
  if not new_ws_root then
    return client.root_dir == new_root
  end

  local _, client_ws_root = workspace_mod.resolve(client.root_dir)
  if new_ws_root ~= client_ws_root then return false end

  -- Same workspace — reuse, but lazily add the new folder
  local new_uri = vim.uri_from_fname(new_root)
  for _, folder in ipairs(client.workspace_folders or {}) do
    if folder.uri == new_uri then return true end -- already has it
  end

  local _, _, folders = workspace_mod.resolve(new_root)
  local abs = vim.fn.fnamemodify(new_root, ":p")
  local folder_name = vim.fn.fnamemodify(new_root, ":t")
  if folders then
    for _, f in ipairs(folders) do
      if abs:find(f.path .. "/", 1, true) == 1 or abs == f.path then
        folder_name = f.name
        break
      end
    end
  end

  client:notify("workspace/didChangeWorkspaceFolders", {
    event = { added = { { uri = new_uri, name = folder_name } }, removed = {} },
  })
  client.workspace_folders = client.workspace_folders or {}
  client.workspace_folders[#client.workspace_folders + 1] = { uri = new_uri, name = folder_name }

  return true
end

-- ── Public API ─────────────────────────────────────────────────────────

--- Get LSP config table for vim.lsp.config.
--- Returns { root_dir, before_init, reuse_client } merged with any overrides.
---@param overrides? table additional config to merge (settings, capabilities, cmd, etc.)
---@return table lsp_config
function M.lsp(overrides)
  local config = {
    root_dir = lsp_root_dir,
    before_init = lsp_before_init,
    reuse_client = lsp_reuse_client,
  }
  if overrides then
    return vim.tbl_deep_extend("force", config, overrides)
  end
  return config
end

return M
