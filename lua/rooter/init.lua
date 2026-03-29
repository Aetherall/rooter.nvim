--- rooter.nvim — Project root detection and VS Code workspace compatibility.
---
--- Usage:
---   require("rooter").setup({})
---   vim.lsp.config("*", require("rooter").lsp())
---
---@class rooter
local M = {}

local root_mod = require("rooter.root")
local workspace_mod = require("rooter.workspace")
local vscode_mod = require("rooter.vscode")
local lsp_mod = require("rooter.lsp")

-- ── Setup ──────────────────────────────────────────────────────────────

local _prev_root = nil
local _on_change_callbacks = {} ---@type fun(root: string, prev_root: string|nil)[]

--- Configure rooter.nvim.
---@param opts? table
---   markers?: string[]  — project markers (default: {".git", "flake.nix", "package.json", ...})
---   exclude?: string[]  — directories that are never project roots (default: {"~", "/", "/tmp"})
---   auto_cd?: boolean   — auto-cd to project root on BufEnter (default: true)
---   cd_scope?: "global"|"tab"|"window"|false — cd scope (default: "global")
function M.setup(opts)
  opts = opts or {}

  -- Configure root detection
  root_mod.configure({
    markers = opts.markers,
    exclude = opts.exclude,
  })

  -- Auto-cd on BufEnter
  local auto_cd = opts.auto_cd ~= false -- default: true
  local cd_scope = opts.cd_scope or "global"

  if auto_cd and cd_scope then
    local cd_cmd = ({ global = "cd", tab = "tcd", window = "lcd" })[cd_scope] or "cd"

    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("rooter_auto_cd", { clear = true }),
      callback = function(args)
        if vim.bo[args.buf].buftype ~= "" then return end
        local fname = vim.api.nvim_buf_get_name(args.buf)
        if fname == "" or fname:match("^%w+://") then return end

        local new_root = root_mod.root(fname)
        if new_root and new_root ~= vim.fn.getcwd() then
          vim.cmd(cd_cmd .. " " .. vim.fn.fnameescape(new_root))

          -- Emit event + callbacks on root change
          if new_root ~= _prev_root then
            local prev = _prev_root
            _prev_root = new_root
            vim.api.nvim_exec_autocmds("User", {
              pattern = "RooterChanged",
              data = { root = new_root, prev_root = prev },
            })
            for _, cb in ipairs(_on_change_callbacks) do
              cb(new_root, prev)
            end
          end
        end
      end,
    })
  end
end

-- ── Re-exports: root detection ─────────────────────────────────────────

M.root = root_mod.root
M.name = root_mod.name
M.is_project = root_mod.is_project
M.has = root_mod.has

--- Register a callback for project root changes.
---@param callback fun(root: string, prev_root: string|nil)
function M.on_change(callback)
  _on_change_callbacks[#_on_change_callbacks + 1] = callback
end

-- ── Re-exports: workspace folders ──────────────────────────────────────

M.folders = workspace_mod.folders
M.folder_for = workspace_mod.folder_for

-- ── Re-exports: LSP integration ────────────────────────────────────────

--- Get LSP config table for vim.lsp.config.
---@param overrides? table additional config to merge (settings, capabilities, cmd, etc.)
---@return table lsp_config
function M.lsp(overrides)
  return lsp_mod.lsp(overrides)
end
M.register_server_settings_prefix = lsp_mod.register_server_settings_prefix

-- ── Re-exports: VS Code interop (raw interpolated data, no UI) ─────────

M.settings = vscode_mod.settings
M.launch_configs = vscode_mod.launch_configs
M.task_configs = vscode_mod.task_configs

return M
