--- Small persistent state (e.g. the journal root chosen with `:Logpose init`),
--- stored as JSON in stdpath("data")/logpose/state.json.
local fs = require("logpose.util.fs")

local M = {}

---@return string
function M.path()
  return fs.join(vim.fn.stdpath("data") --[[@as string]], "logpose", "state.json")
end

---@return table
function M.read()
  local content = fs.read_file(M.path())
  if not content or content == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return {}
  end
  return data
end

---@param key string
---@return any
function M.get(key)
  return M.read()[key]
end

---@param key string
---@param value any
function M.set(key, value)
  local data = M.read()
  data[key] = value
  local ok, err = fs.write_file(M.path(), vim.json.encode(data) .. "\n")
  if not ok then
    error(err, 0)
  end
end

return M
