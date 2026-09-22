---@module "tracks.buffer"
---Identifies normal file buffers that belong in navigation state.

local M = {}

local EXCLUDED_FILETYPES = {
    checkhealth = true,
    dbui = true,
    fff_file_info = true,
    fff_input = true,
    fff_list = true,
    fff_preview = true,
    fzf = true,
    ["git-log"] = true,
    ["git-status"] = true,
    gitcommit = true,
    help = true,
    log = true,
    lspinfo = true,
    messages = true,
    minifiles = true,
    ["minifiles-help"] = true,
    minimap = true,
    mininotify = true,
    ["mininotify-history"] = true,
    minipick = true,
    ministarter = true,
    minitest = true,
    ["no-neck-pain"] = true,
    noice = true,
    notify = true,
    oil = true,
    oil_progress = true,
    qf = true,
}

---@param path string
---@return string|nil
function M.normalize_path(path)
    if path == "" then return nil end
    return vim.fs.normalize(vim.fs.abspath(path))
end

---@param bufnr integer
---@return boolean
function M.is_loaded(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)
end

---@param bufnr integer
---@return string|nil
function M.normal_file_path(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return nil end

    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if EXCLUDED_FILETYPES[filetype] or vim.b[bufnr].tracks_exclude == true then return nil end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" or name:match("^%a[%w+.-]*://") then return nil end
    return M.normalize_path(name)
end

return M
