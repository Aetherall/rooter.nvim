--- rooter.parser — JSONC parser for VS Code configuration files.
--- Handles // comments, trailing commas, and standard JSON.
--- Uses plenary.json if available, falls back to built-in stripping.
---
---@class rooter.parser
local M = {}

--- Strip trailing commas from JSON (,] and ,}).
---@param str string JSON string
---@return string cleaned
local function strip_trailing_commas(str)
  return str:gsub(",%s*]", "]"):gsub(",%s*}", "}")
end

--- Strip single-line // comments from JSON.
--- Respects string boundaries (doesn't strip // inside "...").
---@param str string JSON string
---@return string cleaned
local function strip_line_comments(str)
  return str:gsub("(.-)\n", function(line)
    local in_string = false
    local i = 1
    while i <= #line do
      local c = line:sub(i, i)
      if c == '"' and line:sub(i - 1, i - 1) ~= "\\" then
        in_string = not in_string
      elseif not in_string and c == "/" and line:sub(i + 1, i + 1) == "/" then
        return line:sub(1, i - 1) .. "\n"
      end
      i = i + 1
    end
    return line .. "\n"
  end)
end

--- Parse a JSON file with comments (JSONC).
--- Handles // comments and trailing commas.
---@param file_path string path to the JSON/JSONC file
---@return table|nil data parsed table, or nil on failure
function M.parse_json_file(file_path)
  local f = io.open(file_path, "r")
  if not f then return nil end

  local content = f:read("*a")
  f:close()

  -- Try plenary.json first (robust JSONC handling)
  local ok, plenary_json = pcall(require, "plenary.json")
  if ok then
    content = plenary_json.json_strip_comments(content, {
      whitespace = false,
      trailing_commas = false,
    })
  else
    -- Fallback: built-in comment and trailing comma removal
    content = strip_line_comments(content)
    content = strip_trailing_commas(content)
  end

  local decode_ok, data = pcall(vim.fn.json_decode, content)
  if not decode_ok then return nil end

  return data
end

--- Parse a .code-workspace file (JSONC format).
---@param workspace_file string path to the .code-workspace file
---@return table|nil data parsed workspace data
function M.parse_workspace_file(workspace_file)
  return M.parse_json_file(workspace_file)
end

return M
