---@module "tracks.buffer_cache"
---@brief MRU cache for loaded normal-file buffers.
---
--- Active files are pinned elsewhere. On setup, this module adopts every
--- currently loaded normal-file buffer, ordered by Neovim's available
--- last-used metadata (with newer buffer numbers breaking timestamp ties).
--- It then keeps that order current on `BufReadPost` and `BufEnter`, and
--- removes entries when a buffer unloads. Pruning is a soft limit: visible,
--- modified, pinned, or
--- explicitly protected buffers are retained even when they exceed the limit.

local buf = require("tracks.buffer")
local log = require("tracks.log")

local M = {}

---@class Tracks.BufferCacheConfig
---@field max_buffers number Total normal file buffers to keep loaded.
---@field is_pinned fun(path: string): boolean
---@field augroup_id number?
local default_config = {
    max_buffers = 8,
    is_pinned = function() return false end,
    augroup_id = nil,
}

---@type Tracks.BufferCacheConfig
M.config = vim.tbl_extend("force", {}, default_config)

---@type string[] Most recent first.
M._mru = {}

---@param bufnr number
---@return string?
local function loaded_file_path(bufnr)
    if not buf.is_loaded(bufnr) then return nil end
    return buf.normal_file_path(bufnr)
end

---@param path string
local function remove_from_mru(path)
    for i = #M._mru, 1, -1 do
        if M._mru[i] == path then table.remove(M._mru, i) end
    end
end

---@param bufnr number?
function M.touch(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local path = loaded_file_path(bufnr)
    if not path then return end

    remove_from_mru(path)
    table.insert(M._mru, 1, path)
end

---Adopt loaded normal-file buffers that were present before the cache started.
---Existing MRU entries retain their order; newly discovered buffers are added
---in best-effort last-used order.
local function adopt_loaded_buffers()
    local entries = {}
    local loaded_paths = {}

    for _, info in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
        local path = loaded_file_path(info.bufnr)
        if path then
            loaded_paths[path] = true
            entries[#entries + 1] = {
                bufnr = info.bufnr,
                path = path,
                lastused = info.lastused or 0,
            }
        end
    end

    -- Never retain unloaded or no-longer-normal buffers in this cache.
    for i = #M._mru, 1, -1 do
        if not loaded_paths[M._mru[i]] then table.remove(M._mru, i) end
    end

    local known = {}
    for _, path in ipairs(M._mru) do
        known[path] = true
    end

    table.sort(entries, function(a, b)
        if a.lastused ~= b.lastused then return a.lastused > b.lastused end
        return a.bufnr > b.bufnr
    end)

    for _, entry in ipairs(entries) do
        if not known[entry.path] then
            M._mru[#M._mru + 1] = entry.path
            known[entry.path] = true
        end
    end
end

function M.prune()
    adopt_loaded_buffers()

    local ranks = {}
    for i, path in ipairs(M._mru) do
        ranks[path] = i
    end

    local buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local path = loaded_file_path(bufnr)
        if path then buffers[#buffers + 1] = { bufnr = bufnr, path = path } end
    end

    table.sort(
        buffers,
        function(a, b) return (ranks[a.path] or math.huge) < (ranks[b.path] or math.huge) end
    )

    local loaded_count = #buffers
    if loaded_count <= M.config.max_buffers then return end

    -- Delete coldest buffers first. `buffers` is most-recent-first, so walk it
    -- backwards. Stop when the total normal-file buffer count is back under max.
    for i = #buffers, 1, -1 do
        if loaded_count <= M.config.max_buffers then return end

        local entry = buffers[i]
        local protected = loaded_file_path(entry.bufnr) == nil
        if not protected then
            protected = vim.api.nvim_get_option_value("modified", { buf = entry.bufnr })
        end
        if not protected then
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_get_buf(win) == entry.bufnr then
                    protected = true
                    break
                end
            end
        end
        if not protected then protected = M.config.is_pinned(entry.path) end
        if not protected then
            local ok, value = pcall(vim.api.nvim_buf_get_var, entry.bufnr, "__bufdel_protected")
            protected = ok and value or false
        end

        if not protected then
            local ok, err = pcall(vim.api.nvim_buf_delete, entry.bufnr, { force = false })
            if ok then
                loaded_count = loaded_count - 1
                remove_from_mru(entry.path)
                log.debug("Pruned buffer cache entry", entry.path)
            else
                log.debug("Failed to prune buffer cache entry", entry.path, err)
            end
        end
    end
end

---@return string[] Most recent first.
function M.tracked()
    local paths = {}
    for i, path in ipairs(M._mru) do
        paths[i] = path
    end
    return paths
end

---@param opts Tracks.BufferCacheConfig?
function M.setup(opts)
    M.config = vim.tbl_extend("force", M.config, opts or {})

    adopt_loaded_buffers()
    M.touch(0)
    vim.schedule(M.prune)

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("tracks_buffer_cache", { clear = true })

        vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
            group = M.config.augroup_id,
            desc = "Tracks buffer cache: track loaded and current file buffers",
            callback = function(ev)
                M.touch(ev.buf)
                vim.schedule(M.prune)
            end,
        })

        vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload", "BufDelete", "BufWipeout" }, {
            group = M.config.augroup_id,
            desc = "Tracks buffer cache: remove unloaded files and prune cold buffers",
            callback = function(ev)
                if
                    ev.file ~= ""
                    and (
                        ev.event == "BufUnload"
                        or ev.event == "BufDelete"
                        or ev.event == "BufWipeout"
                    )
                then
                    remove_from_mru(vim.fs.normalize(vim.fs.abspath(ev.file)))
                end

                vim.schedule(M.prune)
            end,
        })

        vim.api.nvim_create_autocmd("User", {
            group = M.config.augroup_id,
            pattern = "TracksActiveUpdated",
            desc = "Tracks buffer cache: prune after active file pins change",
            callback = function() vim.schedule(M.prune) end,
        })
    end
end

return M
