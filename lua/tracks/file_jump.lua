---@module "tracks.file_jump"
---@brief Automatic, restorable file-visit history.
---
--- File jumps are intentionally separate from in-buffer point jumps. Normal
--- file-buffer transitions build a browser-like history. Navigation performed
--- by this module does not create new visits, and paths are reopened when the
--- original buffer has been cleaned up.

local buf = require("tracks.buffer")
local config = require("tracks.config")
local log = require("tracks.log")

local M = {}

local augroup_id = nil

---@class Tracks.FileJumpEntry
---@field path string Absolute normalized path.
---@field view vim.fn.winrestview.dict

---@class Tracks.FileJumpHistory
---@field entries Tracks.FileJumpEntry[]
---@field index number
---@field alternate_index number?

---@type Tracks.FileJumpConfig
M.config = vim.deepcopy(config.defaults.file_jump)

---@type Tracks.FileJumpHistory
M.history = {
    entries = {},
    index = 0,
    alternate_index = nil,
}

-- BufLeave and BufEnter run synchronously while changing the current buffer.
-- This guard makes file_jump's own transitions invisible to automatic history.
M._navigating = false

---@param bufnr number
---@return string?
local function trackable_path(bufnr)
    if not buf.is_loaded(bufnr) then return nil end

    local path = buf.normal_file_path(bufnr)
    if not path then return nil end

    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_filetypes, filetype) then return nil end

    return path
end

---@return vim.fn.winrestview.dict
local function capture_view() return vim.tbl_extend("force", {}, vim.fn.winsaveview()) end

---@param view vim.fn.winrestview.dict
---@return vim.fn.winrestview.dict
local function copy_view(view) return vim.tbl_extend("force", {}, view) end

---@param entry Tracks.FileJumpEntry
local function restore_view(entry)
    local line_count = math.max(1, vim.api.nvim_buf_line_count(0))
    local view = copy_view(entry.view)

    view.lnum = math.max(1, math.min(view.lnum or 1, line_count))
    view.topline = math.max(1, math.min(view.topline or view.lnum, line_count))
    vim.fn.winrestview(view)
end

---@param path string
---@return number? bufnr
---@return boolean missing
local function ensure_loaded(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
        if vim.api.nvim_buf_is_loaded(bufnr) then return bufnr, false end
    end

    if not vim.uv.fs_stat(path) then return nil, true end

    bufnr = vim.fn.bufadd(path)
    if bufnr == 0 then return nil, false end

    vim.fn.bufload(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return nil, false
    end

    return bufnr, false
end

local function truncate_forward()
    local history = M.history
    for i = #history.entries, history.index + 1, -1 do
        table.remove(history.entries, i)
    end
end

local function enforce_limit()
    local history = M.history
    while #history.entries > M.config.max_history do
        table.remove(history.entries, 1)
        history.index = math.max(0, history.index - 1)
        if history.alternate_index then
            history.alternate_index = history.alternate_index - 1
            if history.alternate_index < 1 then history.alternate_index = nil end
        end
    end
end

---@param bufnr number
local function update_current_view(bufnr)
    local history = M.history
    local current = history.entries[history.index]
    if not current then return end

    local path = trackable_path(bufnr)
    if path ~= current.path or vim.api.nvim_get_current_buf() ~= bufnr then return end

    current.view = capture_view()
end

---@param bufnr number
local function record_enter(bufnr)
    local path = trackable_path(bufnr)
    if not path then return end

    local history = M.history
    local current = history.entries[history.index]
    if current and current.path == path then return end

    local previous_index = history.index > 0 and history.index or nil
    truncate_forward()

    history.entries[#history.entries + 1] = {
        path = path,
        view = capture_view(),
    }
    history.index = #history.entries
    history.alternate_index = previous_index

    enforce_limit()
end

---@param target_index number
local function remove_entry(target_index)
    local history = M.history
    table.remove(history.entries, target_index)

    if history.index > target_index then
        history.index = history.index - 1
    elseif history.index == target_index then
        history.index = math.min(history.index, #history.entries)
    end

    if history.alternate_index then
        if history.alternate_index > target_index then
            history.alternate_index = history.alternate_index - 1
        elseif history.alternate_index == target_index then
            history.alternate_index = nil
        end
    end
end

---@param target_index number
---@return boolean moved
---@return boolean missing
local function navigate_to(target_index)
    local history = M.history
    if target_index < 1 or target_index > #history.entries then return false, false end
    if target_index == history.index then return true, false end

    update_current_view(vim.api.nvim_get_current_buf())

    local entry = history.entries[target_index]
    local previous_index = history.index
    local missing, loaded
    M._navigating = true
    local ok, err = xpcall(function()
        loaded, missing = ensure_loaded(entry.path)
        if not loaded then return end
        if vim.api.nvim_get_current_buf() ~= loaded then vim.api.nvim_set_current_buf(loaded) end
        restore_view(entry)
    end, debug.traceback)
    M._navigating = false

    if not ok then
        log.warn("Failed to restore file jump", entry.path, err)
        return false, false
    end
    if missing then
        log.info("Dropping missing file jump", entry.path)
        remove_entry(target_index)
        return false, true
    end
    if not loaded then
        log.info("Cannot restore file jump", entry.path)
        return false, false
    end

    history.index = target_index
    history.alternate_index = previous_index > 0 and previous_index or nil
    return true, false
end

---@param delta -1|1
---@return boolean moved
local function move(delta)
    while true do
        local moved, missing = navigate_to(M.history.index + delta)
        if moved or not missing then return moved end
    end
end

---Move backward through chronological file visits.
---@return boolean moved
function M.prev() return move(-1) end

---Move forward through chronological file visits.
---@return boolean moved
function M.next() return move(1) end

---Toggle between the current visit and the visit most recently left.
---@return boolean moved
function M.toggle()
    local target = M.history.alternate_index
    if not target then return false end
    return navigate_to(target)
end

---Export a detached, portable trail. Capture the focused file's view; when a
---tool buffer is focused, retain the last recorded file view.
---@return Tracks.FileJumpHistory
function M.snapshot()
    update_current_view(vim.api.nvim_get_current_buf())
    local history = M.history
    local entries = {}
    for i, entry in ipairs(history.entries) do
        entries[i] = {
            path = entry.path,
            view = {
                lnum = entry.view.lnum or 1,
                col = entry.view.col or 0,
                topline = entry.view.topline or 1,
                leftcol = entry.view.leftcol or 0,
            },
        }
    end
    return {
        entries = entries,
        index = history.index,
        alternate_index = history.alternate_index,
    }
end

---Adopt a portable trail before or after setup. Callers own storage and scope;
---the currently open file is appended only if it differs from the saved visit.
---@param snapshot Tracks.FileJumpHistory
---@param opts? { record_current: boolean } Disable adoption of the current buffer on scope changes.
function M.import(snapshot, opts)
    if opts ~= nil and (type(opts) ~= "table" or type(opts.record_current) ~= "boolean") then
        error("tracks.file_jump.import(): invalid options", 2)
    end
    if
        type(snapshot) ~= "table"
        or type(snapshot.entries) ~= "table"
        or not vim.islist(snapshot.entries)
    then
        error("tracks.file_jump.import(): expected a trail with entries", 2)
    end
    local count = #snapshot.entries
    local index = snapshot.index
    local alternate = snapshot.alternate_index
    if
        type(index) ~= "number"
        or index % 1 ~= 0
        or index < 0
        or index > count
        or (index == 0 and count ~= 0)
        or (
            alternate ~= nil
            and (
                type(alternate) ~= "number"
                or alternate % 1 ~= 0
                or alternate < 1
                or alternate > count
            )
        )
    then
        error("tracks.file_jump.import(): invalid trail indices", 2)
    end
    local entries = {}
    for i, entry in ipairs(snapshot.entries) do
        local view = type(entry) == "table" and entry.view or nil
        if
            type(entry) ~= "table"
            or type(entry.path) ~= "string"
            or not vim.startswith(entry.path, "/")
            or vim.fs.normalize(entry.path) ~= entry.path
            or type(view) ~= "table"
        then
            error(("tracks.file_jump.import(): invalid entry %d"):format(i), 2)
        end
        for _, key in ipairs({ "lnum", "col", "topline", "leftcol" }) do
            local value = view[key]
            local minimum = (key == "lnum" or key == "topline") and 1 or 0
            if type(value) ~= "number" or value % 1 ~= 0 or value < minimum then
                error(("tracks.file_jump.import(): invalid %s in entry %d"):format(key, i), 2)
            end
        end
        entries[i] = { path = entry.path, view = copy_view(view) }
    end
    M.history = { entries = entries, index = index, alternate_index = alternate }
    enforce_limit()
    if opts == nil or opts.record_current then record_enter(vim.api.nvim_get_current_buf()) end
end

---Forget all visits and seed history from the current buffer when possible.
function M.reset()
    M.history = {
        entries = {},
        index = 0,
        alternate_index = nil,
    }
    M._navigating = false
    record_enter(vim.api.nvim_get_current_buf())
end

---@param normalized Tracks.FileJumpConfig
function M._setup(normalized)
    M.config = vim.deepcopy(normalized)

    if not augroup_id then
        augroup_id = vim.api.nvim_create_augroup("tracks_file_jump", { clear = true })

        vim.api.nvim_create_autocmd("BufLeave", {
            group = augroup_id,
            desc = "Tracks file history: save the departing visit",
            callback = function(ev)
                if not M._navigating then update_current_view(ev.buf) end
            end,
        })

        vim.api.nvim_create_autocmd("BufEnter", {
            group = augroup_id,
            desc = "Tracks file history: record an entered file",
            callback = function(ev)
                if not M._navigating then record_enter(ev.buf) end
            end,
        })
    end

    record_enter(vim.api.nvim_get_current_buf())
end

if vim.g.tracks_test then
    M._test = {
        record_enter = record_enter,
        trackable_path = trackable_path,
        update_current_view = update_current_view,
    }
end

return M
