# rooter.nvim

Project root detection and VS Code workspace compatibility for Neovim.

rooter.nvim answers two questions every development tool needs:
**"What project am I in?"** and **"How is it structured?"**

It replaces the scattered `vim.fs.root()` calls, custom workspace modules,
and ad-hoc `vim.fn.getcwd()` usage with a single unified API.

## Features

- **Project root detection** — walks up from the current file looking for `.git`, `package.json`, `Cargo.toml`, etc. Returns nil for non-project directories (`~`, `/`, `/tmp`).
- **VS Code `.code-workspace` support** — parses workspace files, resolves multi-root folder structures.
- **LSP integration** — drop-in `root_dir`, `before_init`, and `reuse_client` for `vim.lsp.config`. Injects per-folder settings, lazily adds workspace folders.
- **VS Code config reading** — reads and merges `settings.json`, `launch.json`, `tasks.json` from all workspace folders with full `${workspaceFolder}` variable interpolation.
- **Auto-cd on BufEnter** — configurable scope (global, tab, window).
- **Project change callbacks** — `on_change(fn)` fires when the project root changes.
- **Project file detection** — `has({"biome.jsonc", "biome.json"})` checks if the project contains specific files, ordered by priority.
- **Safety guard** — `root()` returns nil for home directory, filesystem root, and `/tmp`. Prevents tools from indexing `~` or starting LSP servers for non-projects.

## What makes it different

| | vim-rooter | project.nvim | LazyVim | rooter.nvim |
|---|---|---|---|---|
| `.code-workspace` support | No | No | No | Yes |
| LSP workspace folders | No | No | Partial | Full |
| VS Code settings/launch/tasks | No | No | No | Yes |
| `${workspaceFolder}` interpolation | No | No | No | Yes |
| Safety guard (nil for `~`) | No | No | No | Yes |
| Auto-cd (configurable scope) | VimScript | Archived | Distro-only | Yes |
| Built on `vim.fs.root()` | No | No | No | Yes |

## Installation

### lazy.nvim

```lua
{
  dir = "~/workspace/opensource/rooter.nvim",
  lazy = false,
  config = function()
    require("rooter").setup()
  end,
}
```

### Nix flake

```nix
# As a flake input:
inputs.rooter-nvim.url = "path:/home/user/workspace/opensource/rooter.nvim";

# In your neovim plugin list:
rooter-nvim.packages.${system}.default
```

## Quick start

```lua
-- Minimal setup: auto-cd enabled, global scope
require("rooter").setup()

-- LSP: workspace-aware root_dir, settings injection, multi-root reuse
vim.lsp.config("*", require("rooter").lsp())

-- Server-specific overrides merge with rooter's callbacks
vim.lsp.config("vtsls", require("rooter").lsp({
  settings = {
    typescript = { tsserver = { maxTsServerMemory = 16384 } },
  },
}))
```

## API

### Setup

#### `rooter.setup(opts?)`

Configure rooter.nvim. All options are optional.

```lua
require("rooter").setup({
  markers = { ".git", "flake.nix", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Makefile" },
  exclude = { "~", "/", "/tmp" },
  auto_cd = true,         -- auto-cd on BufEnter (default: true)
  cd_scope = "global",    -- "global" | "tab" | "window" (default: "global")
})
```

### Project root

#### `rooter.root(path?)`

Find the project root for a file path or the current context.

**Resolution order:**
1. `vim.fs.root(path, markers)` — walk up from the given path, return the nearest marker match.
2. `vim.fn.getcwd()` — if no path given and cwd is a project, return it (respects `:tcd` from project switchers).
3. `nil` — not in a project.

If a path is given but no markers are found above it, returns nil (does not fall back to cwd). This prevents returning the wrong project when a file is in a non-project subdirectory.

```lua
rooter.root()                          -- from current buffer/cwd
rooter.root("~/workspace/kraaft/monorepo/src/auth/service.ts")
-- => "/home/user/workspace/kraaft/monorepo"

rooter.root("~/random/file.txt")       -- no markers found
-- => nil

rooter.root("~")                       -- excluded directory
-- => nil
```

#### `rooter.name(path?)`

Last path segment of the project root.

```lua
rooter.name()  -- => "monorepo"
```

#### `rooter.is_project(dir)`

Check if a directory has project markers. Returns false for excluded directories.

```lua
rooter.is_project("/home/user/workspace/kraaft/monorepo")  -- => true
rooter.is_project("/home/user")                             -- => false
```

#### `rooter.has(markers, path?)`

Check if the project contains specific files or directories. Accepts a string or a list of strings (checked in order, first match wins). Returns the absolute path to the first match, or nil.

```lua
rooter.has(".git")                              -- => "/home/.../project/.git"
rooter.has({ "biome.jsonc", "biome.json" })     -- => "/home/.../project/biome.json"
rooter.has("nonexistent.txt")                   -- => nil
```

#### `rooter.on_change(callback)`

Register a callback that fires when the project root changes (via auto-cd). The callback receives `(new_root, prev_root)`.

```lua
rooter.on_change(function(root, prev)
  print("Switched from " .. (prev or "nil") .. " to " .. root)
end)
```

The `User RooterChanged` autocmd also fires with `{ root, prev_root }` data.

### Workspace folders

#### `rooter.folders(path?)`

Get workspace folders for the current context. If a `.code-workspace` file is found, returns its folders. Otherwise returns a single-element list with the project root.

```lua
rooter.folders()
-- With .code-workspace: { {path="/home/.../frontend", name="Frontend"}, {path="/home/.../backend", name="Backend"} }
-- Without: { {path="/home/.../project", name="project"} }
```

#### `rooter.folder_for(path?)`

Find which workspace folder contains a given file. Falls back to the project root if no `.code-workspace` exists.

```lua
rooter.folder_for("/home/.../frontend/src/app.ts")
-- => "/home/.../frontend"
```

### LSP integration

#### `rooter.lsp(overrides?)`

Returns a table with `root_dir`, `before_init`, and `reuse_client` for `vim.lsp.config`. Pass optional overrides (settings, capabilities, etc.) to deep-merge with the base config.

```lua
-- Apply to all servers:
vim.lsp.config("*", rooter.lsp())

-- Server-specific overrides:
vim.lsp.config("vtsls", rooter.lsp({
  settings = { typescript = { tsserver = { maxTsServerMemory = 16384 } } },
}))
```

**`root_dir(bufnr, on_dir)`** resolution:

1. Workspace folder containing the buffer (from `.code-workspace`)
2. Workspace root (directory containing `.code-workspace`)
3. `.vscode` directory within the `.git` boundary
4. `.git` root
5. `nil` — `on_dir` not called, LSP doesn't start

When `root_dir` returns nil, the LSP server never starts. This prevents servers from indexing broad directories like `~/.config` or `$HOME`.

**`before_init(params, config)`**:

- Injects settings from `.vscode/settings.json` (extracted by server name prefix, e.g., `"typescript.*"` for vtsls).
- Sets `workspace_folders` to only the folder containing `root_dir` (not all folders — prevents eager loading of all tsconfigs in a monorepo).
- Installs `workspace/configuration` handler for per-folder settings at runtime.

**`reuse_client(client, config)`**:

- Reuses LSP clients within the same `.code-workspace`. When a buffer from a different workspace folder opens, the existing client is reused and the new folder is lazily added via `workspace/didChangeWorkspaceFolders`.
- Without a `.code-workspace`, falls back to default behavior (reuse only if `root_dir` matches).

#### `rooter.register_server_settings_prefix(server_name, prefix)`

Register a custom VS Code setting prefix for an LSP server. Used for extracting server-specific settings from `.vscode/settings.json`.

```lua
rooter.register_server_settings_prefix("my_custom_ls", "myLanguage")
-- Now settings.json { "myLanguage.foo": "bar" } → config.settings.myLanguage.foo = "bar"
```

Built-in prefixes: `pyright→python`, `vtsls→typescript`, `lua_ls→Lua`, `biome→biome`, `nixd→nix`, `gopls→gopls`, `rust_analyzer→rust-analyzer`, and others.

### VS Code config

#### `rooter.settings(path?)`

Get merged settings from `.code-workspace` + `.vscode/settings.json`. Variables are interpolated.

```lua
rooter.settings()
-- => { ["editor.tabSize"] = 2, ["typescript.tsdk"] = "/home/.../node_modules/typescript/lib" }
```

#### `rooter.launch_configs(path?)`

Get merged launch configurations from all workspace folders' `.vscode/launch.json` + the workspace-level launch section. Variables are interpolated. Each configuration has a `__folder` field indicating its source folder.

```lua
rooter.launch_configs()
-- => { configurations = { {name="Launch", program="/home/.../src/index.ts", __folder="backend"}, ... }, compounds = { ... } }
```

#### `rooter.task_configs(path?)`

Get merged task configurations from all workspace folders' `.vscode/tasks.json`. Variables are interpolated.

```lua
rooter.task_configs()
-- => { tasks = { {label="build", command="npm run build", __folder="frontend"}, ... } }
```

## How it works

### Two concepts, one API

**Project root** is the top-level directory (where `.git` lives). Tools like grep, semantic search, sessions, and auto-cd use this.

**Workspace folder** is a sub-directory within a monorepo (a specific package). LSP, test runners, and debuggers use this.

```
rooter.root()       → ~/workspace/kraaft/monorepo          (.git at top)
rooter.folders()    → [ ~/workspace/kraaft/monorepo/frontend,
                         ~/workspace/kraaft/monorepo/backend ]
rooter.folder_for() → ~/workspace/kraaft/monorepo/backend  (for this file)
```

### Resolution priority

When `rooter.root()` is called with a path, it walks up looking for markers. The nearest match wins. This means in a monorepo, `rooter.root()` returns the monorepo root (`.git`), not a sub-package (`package.json`).

When called without a path (no buffer context), it checks `vim.fn.getcwd()`. This respects `:tcd` from project switchers — after switching projects, `rooter.root()` returns the new project immediately, even before opening a file.

### Safety

`rooter.root()` returns nil for directories in the exclude list (`~`, `/`, `/tmp`). This propagates through the entire system:

- **Auto-cd**: skips (doesn't cd to `~`)
- **LSP**: `root_dir` returns nil → server doesn't start
- **Session restore**: guarded by `rooter.root() ~= nil`
- **Search tools**: can check for nil and show "not in a project"

### VS Code interop

rooter.nvim reads `.code-workspace` files (JSONC with comments and trailing commas) to resolve workspace folders. It reads `.vscode/settings.json`, `launch.json`, and `tasks.json` from each folder, merges them, and interpolates VS Code variables:

- `${workspaceFolder}` — resolved to the workspace folder's absolute path
- `${workspaceFolderBasename}` — folder name
- `${env:VAR}` — environment variable
- `${config:key.path}` — workspace settings lookup
- `${file}`, `${fileBasename}`, `${fileDirname}` — current buffer
- `${lua:expression}` — Lua expression evaluation (rooter extension)

## Recipes

### Session persistence with persistence.nvim

```lua
-- In your persistence.nvim config:
local persistence = require("persistence")
local rooter = require("rooter")

-- Only restore session on startup if in a project
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.fn.argc() > 0 then return end
    if rooter.root() then
      persistence.load()
      vim.notify("Session restored", vim.log.levels.INFO, { title = rooter.name() })
    end
  end,
})

-- Only auto-save if in a project
vim.api.nvim_create_autocmd("FocusLost", {
  callback = function()
    if rooter.root() and persistence.active() then
      persistence.save()
    end
  end,
})

-- Save session before project switch
rooter.on_change(function(_, prev)
  if prev and persistence.active() then
    persistence.save()
    vim.notify("Session saved", vim.log.levels.INFO, { title = rooter.name(prev) })
  end
end)

-- Scrub non-file buffers before session save
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local bt = vim.bo[buf].buftype
        local name = vim.api.nvim_buf_get_name(buf)
        if bt ~= "" or name == "" or name:match("^%w+://") then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
  end,
})
```

### Conditional tool configuration

```lua
-- Only configure biome if the project has a biome config
local biome_cfg = rooter.has({ "biome.jsonc", "biome.json" })
if biome_cfg then
  -- biome is available in this project
end

-- Resolve a tool binary from the project's workspace folder
local folder = rooter.folder_for()
if folder then
  local jest = folder .. "/node_modules/.bin/jest"
  if vim.fn.executable(jest) == 1 then
    -- use this jest binary
  end
end
```

### Statusline

```lua
-- In lualine config:
lualine.setup({
  sections = {
    lualine_c = {
      function()
        return require("rooter").name() or ""
      end,
    },
  },
})
```

### Semantic search (osgrep)

```lua
-- Use rooter.root() as the search cwd
local root = require("rooter").root()
if root then
  vim.system({ "osgrep", "search", query }, { cwd = root })
end

-- Auto-start a per-project server
rooter.on_change(function(root)
  -- clear caches, restart tools for the new project
end)
```

## Architecture

```
lua/rooter/
  init.lua          -- setup() + auto-cd + public API re-exports
  root.lua          -- root(), is_project(), name(), has()
  workspace.lua     -- .code-workspace parsing, folders(), folder_for()
  lsp.lua           -- lsp() -> {root_dir, before_init, reuse_client}
  vscode.lua        -- settings(), launch_configs(), task_configs()
  parser.lua        -- JSONC parser (comments, trailing commas)
  interpolate.lua   -- ${workspaceFolder} variable expansion
```

## Testing

```bash
# Local (downloads mini.nvim to deps/)
make test

# Nix
nix flake check
```

62 tests across 4 test files covering root detection, JSONC parsing, variable interpolation, and workspace folder resolution.

## License

MIT
