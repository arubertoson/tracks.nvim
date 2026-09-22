---@module "tracks.active"
---@brief Small persisted working set of active files.

local buf = require("tracks.buffer")
local scope = require("tracks.scope")
local log = require("tracks.log")

local M = {}

---@class Tracks.ActiveConfig
---@field max_files number
---@field storage_path string
---@field before_select fun()? Called before switching to an active file.
---@field augroup_id number?
local default_config = {
    max_files = 3,
    storage_path = vim.fs.joinpath(vim.fn.stdpath("state"), "tracks-active.json"),
    before_select = nil,
    augroup_id = nil,
}

---@class Tracks.ActiveItem
---@field path string Absolute normalized path.
---@field bufnr number?

---@class Tracks.ActiveScope
---@field root string
---@field branch string

---@type Tracks.ActiveConfig
M.config = vim.tbl_extend("force", {}, default_config)

---@type string[] Absolute normalized paths.
M._items = {}

---@type table<string, table<string, string[]>>
M._store = {}

M._store_loaded = false

---@type Tracks.ActiveScope?
M._scope = nil

local normalize = buf.normalize_path

---@param path string?
---@return Tracks.ActiveScope?
local function scope_for(path) return scope.for_source(path or vim.api.nvim_buf_get_name(0)) end

local function emit_updated()
    vim.api.nvim_exec_autocmds("User", {
        pattern = "TracksActiveUpdated",
        modeline = false,
        data = {
            scope = M._scope,
            items = M.items(),
        },
    })
end

---@param path string
---@param encoded string
---@return boolean
local function write_store(path, encoded)
    local temporary_path = ("%s.tmp.%d"):format(path, vim.uv.os_getpid())
    local ok, result =
        pcall(vim.fn.writefile, vim.split(encoded, "\n", { plain = true }), temporary_path)
    if not ok or result ~= 0 then
        vim.uv.fs_unlink(temporary_path)
        log.warn("Failed to write active store", temporary_path, result)
        return false
    end

    local renamed, err = vim.uv.fs_rename(temporary_path, path)
    if not renamed then
        vim.uv.fs_unlink(temporary_path)
        log.warn("Failed to replace active store", path, err)
        return false
    end

    return true
end

local function commit()
    local scope = M._scope or scope_for()
    if not scope then return end
    M._scope = scope

    local rels = {}
    for _, path in ipairs(M._items) do
        local rel = vim.fs.relpath(scope.root, path)
        rels[#rels + 1] = rel or path
    end

    M._store[scope.root] = M._store[scope.root] or {}
    M._store[scope.root][scope.branch] = rels

    vim.fs.mkdir(vim.fs.dirname(M.config.storage_path), { parents = true })

    local ok, encoded = pcall(vim.json.encode, M._store)
    if not ok then
        log.warn("Failed to encode active store", encoded)
        return
    end

    if write_store(M.config.storage_path, encoded) then emit_updated() end
end

local function refresh_scope()
    -- Store loading is intentionally coupled to scope refresh: any caller that
    -- needs current active files also needs the persisted store to be ready.
    local loaded_store = false
    if not M._store_loaded then
        local path = M.config.storage_path
        if vim.fn.filereadable(path) ~= 1 then
            M._store = {}
        else
            local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
            if ok and type(decoded) == "table" then
                M._store = decoded
            else
                log.warn("Failed to read active store", path)
                M._store = {}
            end
        end

        M._store_loaded = true
        loaded_store = true
    end

    local scope = scope_for()
    if not scope then return end
    if
        not loaded_store
        and M._scope
        and M._scope.root == scope.root
        and M._scope.branch == scope.branch
    then
        return
    end

    M._scope = scope
    M._items = {}

    local by_root = M._store[scope.root]
    local stored_items = type(by_root) == "table" and by_root[scope.branch] or nil

    for _, stored in ipairs(type(stored_items) == "table" and stored_items or {}) do
        if #M._items >= M.config.max_files then break end

        if type(stored) ~= "string" then
            log.warn("active: ignoring invalid stored path")
        else
            local path = stored:sub(1, 1) == "/" and normalize(stored)
                or normalize(vim.fs.joinpath(scope.root, stored))
            if path then M._items[#M._items + 1] = path end
        end
    end

    emit_updated()
end

---@param path string
---@return number?
local function index_of_path(path)
    for i, item_path in ipairs(M._items) do
        if item_path == path then return i end
    end

    return nil
end

---@param target number|string|nil
---@return string?
local function path_from_target(target)
    if type(target) == "number" then return M._items[target] end

    if type(target) == "string" then return normalize(target) end
    if target == nil then return buf.normal_file_path(vim.api.nvim_get_current_buf()) end

    error(("invalid active-file target: %s"):format(type(target)))
end

---@param slot number
---@param path string
---@return boolean
local function set_slot(slot, path)
    if slot < 1 or slot > M.config.max_files then return false end
    if not M._items[slot] and slot ~= #M._items + 1 then return false end

    local existing = index_of_path(path)
    if existing and existing ~= slot then return false end

    M._items[slot] = path
    commit()

    return true
end

---@param target number|string|nil
---@return number?
function M.index_of(target)
    local path = path_from_target(target)
    if not path then return nil end

    return index_of_path(path)
end

---@param target number|string|nil
---@return boolean
function M.contains(target)
    local path = path_from_target(target)
    if not path then return false end

    return index_of_path(path) ~= nil
end

---@return Tracks.ActiveItem[]
function M.items()
    local items = {}
    for i, path in ipairs(M._items) do
        local bufnr = vim.fn.bufnr(path)
        items[i] = {
            path = path,
            bufnr = bufnr ~= -1 and bufnr or nil,
        }
    end
    return items
end

---@param bufnr number?
---@return boolean added
function M.add(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local path = buf.normal_file_path(bufnr)
    if not path then return false end

    refresh_scope()

    if #M._items >= M.config.max_files then
        vim.notify(
            ("Active files full (%d/%d)"):format(#M._items, M.config.max_files),
            vim.log.levels.INFO
        )
        return false
    end

    return set_slot(#M._items + 1, path)
end

---@param target number|string|nil Slot, path, or current buffer when nil.
---@return boolean removed
function M.remove(target)
    refresh_scope()

    local path = path_from_target(target)
    if not path then return false end

    local index = index_of_path(path)
    if not index then return false end

    table.remove(M._items, index)
    commit()

    return true
end

---@param slot number Slot to replace. Can also fill the next empty slot.
---@param bufnr number?
---@return boolean replaced
function M.replace(slot, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local path = buf.normal_file_path(bufnr)
    if not path then return false end

    refresh_scope()

    return set_slot(slot, path)
end

---@return number removed
function M.remove_all()
    refresh_scope()

    local removed = #M._items
    if removed == 0 then return 0 end

    M._items = {}
    commit()

    return removed
end

---@param slot number
---@return boolean selected
function M.select(slot)
    refresh_scope()

    local path = M._items[slot]
    if not path then return false end

    if M.config.before_select then M.config.before_select() end

    local bufnr = vim.fn.bufnr(path)
    if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then bufnr = nil end

    if not bufnr then
        if not vim.uv.fs_stat(path) then
            vim.notify("Active file no longer exists: " .. path, vim.log.levels.WARN)
            table.remove(M._items, slot)
            commit()
            return false
        end

        bufnr = vim.fn.bufadd(path)
        vim.fn.bufload(bufnr)
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then return false end

    vim.api.nvim_set_current_buf(bufnr)
    emit_updated()

    return true
end

---@param opts Tracks.ActiveConfig?
function M.setup(opts)
    if opts and opts.storage_path and opts.storage_path ~= M.config.storage_path then
        M._store_loaded = false
    end

    M.config = vim.tbl_extend("force", M.config, opts or {})

    refresh_scope()

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("tracks_active", { clear = true })

        vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
            group = M.config.augroup_id,
            desc = "Tracks active files: refresh project/branch scope",
            callback = refresh_scope,
        })
    end
end

return M
