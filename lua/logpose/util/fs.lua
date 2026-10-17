--- Filesystem helpers. Every write in logpose goes through `write_file`:
--- it refuses to touch files with unsaved buffer changes, writes atomically
--- (temp file + rename) and reloads clean buffers showing the file.
local M = {}

local uv = vim.uv or vim.loop

---@param ... string
---@return string
function M.join(...)
  return vim.fs.joinpath(...)
end

---@param path string
---@return string
function M.normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
end

---@param path string
---@return boolean
function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

---@param path string
---@return boolean
function M.is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

---@param dir string
function M.mkdir_p(dir)
  if not M.is_dir(dir) then
    vim.fn.mkdir(dir, "p")
  end
end

--- Read a whole file. Returns nil, err if it can't be read.
---@param path string
---@return string? content, string? err
function M.read_file(path)
  local f, err = io.open(path, "rb")
  if not f then
    return nil, err
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Read a file as lines (split on "\n"; a trailing newline yields a final "").
---@param path string
---@return string[]? lines, string? err
function M.read_lines(path)
  local content, err = M.read_file(path)
  if not content then
    return nil, err
  end
  return vim.split(content, "\n", { plain = true })
end

local function canonical(path)
  local abs = M.normalize(path)
  return uv.fs_realpath(abs) or abs
end

--- Loaded buffer showing `path`, if any.
---@param path string
---@return integer?
function M.find_buf(path)
  local target = canonical(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and canonical(name) == target then
        return buf
      end
    end
  end
  return nil
end

--- Check that none of `paths` has unsaved changes in a buffer.
---@param paths string[]
---@return boolean ok, string? err
function M.check_writable(paths)
  for _, path in ipairs(paths) do
    local buf = M.find_buf(path)
    if buf and vim.bo[buf].modified then
      return false,
        ("logpose: %s has unsaved changes; save or discard them first"):format(vim.fn.fnamemodify(path, ":~"))
    end
  end
  return true
end

--- Reload a clean buffer showing `path` so it reflects what's on disk.
---@param path string
function M.reload(path)
  local buf = M.find_buf(path)
  if buf and not vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! edit")
    end)
  end
end

--- Atomically write `content` to `path`, creating parent directories.
--- Refuses (returns false, err) if a buffer showing `path` has unsaved changes.
---@param path string
---@param content string
---@param opts? { tidy?: boolean, raw?: boolean }  tidy: normalize blank lines for markdownlint;
---  raw: write exactly `content` (no `modified:` bump), e.g. to restore a file
---@return boolean ok, string? err
function M.write_file(path, content, opts)
  if opts and opts.tidy then
    local lines = vim.split(content, "\n", { plain = true })
    content = table.concat(require("logpose.markdown").tidy(lines), "\n") .. "\n"
  end
  if path:sub(-3) == ".md" and not (opts and opts.raw) then
    content = require("logpose.timestamps").touch_text(content) -- bump `modified:`
  end
  local ok, err = M.check_writable({ path })
  if not ok then
    return false, err
  end
  M.mkdir_p(vim.fs.dirname(path))

  local tmp = ("%s.logpose-%d-%d.tmp"):format(path, uv.os_getpid(), uv.hrtime())
  local f, open_err = io.open(tmp, "wb")
  if not f then
    return false, ("logpose: cannot write %s: %s"):format(path, open_err)
  end
  local wrote, write_err = f:write(content)
  f:close()
  if not wrote then
    os.remove(tmp)
    return false, ("logpose: cannot write %s: %s"):format(path, write_err)
  end

  -- Keep the original file's permissions.
  local st = uv.fs_stat(path)
  if st then
    uv.fs_chmod(tmp, st.mode % 4096)
  end

  local renamed, rename_err = uv.fs_rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, ("logpose: cannot replace %s: %s"):format(path, rename_err)
  end

  M.reload(path)
  return true
end

--- Apply `transform(lines) -> new_lines|nil` to a file (lines without trailing newline).
--- If a buffer showing the file has unsaved changes, the buffer is edited instead and left
--- unsaved, so nothing the user typed is lost.
---@param path string
---@param transform fun(lines: string[]): string[]?
---@param opts? { tidy?: boolean }  tidy: normalize blank lines for markdownlint (markdown.tidy)
---@return boolean ok, string? err, "file"|"buffer"|nil changed
function M.update_lines(path, transform, opts)
  local tidy = opts and opts.tidy
  local buf = M.find_buf(path)
  if buf and vim.bo[buf].modified then
    local new = transform(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if not new then
      return true, nil, nil
    end
    if tidy then
      new = require("logpose.markdown").tidy(new)
    end
    new = require("logpose.timestamps").touch(new)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
    return true, nil, "buffer"
  end
  local content, read_err = M.read_file(path)
  if not content then
    return false, ("logpose: cannot read %s: %s"):format(path, read_err)
  end
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  local new = transform(lines)
  if not new then
    return true, nil, nil
  end
  local ok, err = M.write_file(path, table.concat(new, "\n") .. "\n", { tidy = tidy })
  if not ok then
    return false, err
  end
  return true, nil, "file"
end

return M
