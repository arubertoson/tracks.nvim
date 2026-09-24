---@module "tracks.scope"
---Synchronous nearest workspace scope for persisted active files.

local M = {}

---@param path string|nil
---@return string|nil
local function normalize(path)
    if not path or path == "" then return nil end
    return vim.fs.normalize(vim.fs.abspath(path))
end

---@param source string|integer|nil
---@return string|nil
local function path_from_source(source)
    if type(source) == "number" then
        if not vim.api.nvim_buf_is_valid(source) then return nil end
        return normalize(vim.api.nvim_buf_get_name(source))
    end
    if type(source) == "string" then return normalize(source) end
    return normalize(vim.api.nvim_buf_get_name(0))
end

---@param root string
---@return string|nil
local function git_dir(root)
    local dotgit = vim.fs.joinpath(root, ".git")
    local stat = vim.uv.fs_stat(dotgit)
    if not stat then return nil end
    if stat.type == "directory" then return dotgit end
    if stat.type ~= "file" then return nil end

    local ok, lines = pcall(vim.fn.readfile, dotgit, "", 1)
    local target = ok and lines[1] and lines[1]:match("gitdir:%s*(.+)") or nil
    if not target then return nil end
    if not vim.startswith(target, "/") then target = vim.fs.joinpath(root, target) end
    return normalize(target)
end

---@param root string
---@return string
local function branch(root)
    local directory = git_dir(root)
    if not directory then return "-" end

    local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(directory, "HEAD"), "", 1)
    local head = ok and lines[1] or nil
    if not head or head == "" then return "-" end
    return head:match("^ref:%s*refs/heads/(.+)$") or head:sub(1, 12)
end

---@class Tracks.Scope
---@field root string
---@field branch string

---@param source string|integer|nil
---@return Tracks.Scope|nil
function M.for_source(source)
    local path = path_from_source(source)
    if not path then return nil end

    local root = vim.fs.root(path, { ".jj", ".git" })
        or normalize(vim.uv.cwd() or vim.fs.dirname(path) or path)
    if not root then return nil end
    root = normalize(root)
    local jj = vim.uv.fs_stat(vim.fs.joinpath(root, ".jj"))
    return { root = root, branch = jj and "-" or branch(root) }
end

return M
