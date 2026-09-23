---@module "tracks.config"
---Public configuration defaults and boundary validation.

local M = {}

---@class Tracks.PointJumpConfig
---@field debounce_ms integer
---@field max_history integer
---@field min_block_lines integer
---@field max_semantic_area_lines integer
---@field locality_lines integer
---@field max_ts_field_len integer
---@field capture_priority table<string, number>
---@field exclude_filetypes string[]

---@class Tracks.PointJumpOpts
---@field debounce_ms? integer
---@field max_history? integer
---@field min_block_lines? integer
---@field max_semantic_area_lines? integer
---@field locality_lines? integer
---@field max_ts_field_len? integer
---@field capture_priority? table<string, number>
---@field exclude_filetypes? string[]

---@class Tracks.FileJumpConfig
---@field max_history integer
---@field exclude_filetypes string[]

---@class Tracks.FileJumpOpts
---@field max_history? integer
---@field exclude_filetypes? string[]

---@class Tracks.ActiveConfig
---@field max_files integer
---@field storage_path string
---@field before_select fun()? Called before switching to an active file.

---@class Tracks.ActiveOpts
---@field max_files? integer
---@field storage_path? string
---@field before_select? fun() Called before switching to an active file.

---@class Tracks.BufferCacheConfig
---@field max_buffers integer Total normal file buffers to keep loaded.

---@class Tracks.BufferCacheOpts
---@field max_buffers? integer

---@class Tracks.Keymaps
---@field file_prev? string|false
---@field file_next? string|false
---@field point_prev? string|false
---@field point_next? string|false
---@field file_toggle? string|false

---@class Tracks.Opts
---@field point_jump? Tracks.PointJumpOpts
---@field file_jump? Tracks.FileJumpOpts
---@field active? Tracks.ActiveOpts
---@field buffer_cache? Tracks.BufferCacheOpts
---@field keymaps? Tracks.Keymaps|false

---@class Tracks.Config
---@field point_jump Tracks.PointJumpConfig
---@field file_jump Tracks.FileJumpConfig
---@field active Tracks.ActiveConfig
---@field buffer_cache Tracks.BufferCacheConfig
---@field keymaps Tracks.Keymaps|false

---@type Tracks.Config
M.defaults = {
    point_jump = {
        debounce_ms = 250,
        max_history = 10,
        min_block_lines = 12,
        max_semantic_area_lines = 30,
        locality_lines = 20,
        max_ts_field_len = 32,
        capture_priority = {
            ["block.outer"] = 1,
            ["function.outer"] = 2,
            ["method.outer"] = 2,
            ["class.outer"] = 3,
        },
        exclude_filetypes = {},
    },
    file_jump = {
        max_history = 100,
        exclude_filetypes = {},
    },
    active = {
        max_files = 3,
        storage_path = vim.fs.joinpath(vim.fn.stdpath("state"), "tracks-active.json"),
        before_select = nil,
    },
    buffer_cache = {
        max_buffers = 8,
    },
    keymaps = {
        file_prev = "<M-h>",
        file_next = "<M-l>",
        point_prev = "<M-k>",
        point_next = "<M-j>",
        file_toggle = "<M-t>",
    },
}

---@param path string
---@param expected string
---@param value any
local function invalid_type(path, expected, value)
    error(("tracks.setup(): %s must be %s, got %s"):format(path, expected, type(value)), 0)
end

---@param value any
---@param path string
local function expect_table(value, path)
    if type(value) ~= "table" then invalid_type(path, "a table", value) end
end

---@param value any
---@param path string
---@param minimum integer
local function expect_integer(value, path, minimum)
    if type(value) ~= "number" or value % 1 ~= 0 then invalid_type(path, "an integer", value) end
    if value < minimum then
        error(("tracks.setup(): %s must be at least %d"):format(path, minimum), 0)
    end
end

---@param value any
---@param path string
local function expect_string_list(value, path)
    if type(value) ~= "table" or not vim.islist(value) then
        invalid_type(path, "a list of strings", value)
    end
    for index, item in ipairs(value) do
        if type(item) ~= "string" then
            invalid_type(("%s[%d]"):format(path, index), "a string", item)
        end
    end
end

---@param value table
---@param allowed table<string, true>
---@param path string
local function reject_unknown(value, allowed, path)
    for key in pairs(value) do
        if type(key) ~= "string" or not allowed[key] then
            error(("tracks.setup(): unknown option %s.%s"):format(path, tostring(key)), 0)
        end
    end
end

local section_keys = {
    point_jump = true,
    file_jump = true,
    active = true,
    buffer_cache = true,
    keymaps = true,
}

local keymap_keys = {
    file_prev = true,
    file_next = true,
    point_prev = true,
    point_next = true,
    file_toggle = true,
}

local point_keys = {
    debounce_ms = true,
    max_history = true,
    min_block_lines = true,
    max_semantic_area_lines = true,
    locality_lines = true,
    max_ts_field_len = true,
    capture_priority = true,
    exclude_filetypes = true,
}

local file_keys = {
    max_history = true,
    exclude_filetypes = true,
}

local active_keys = {
    max_files = true,
    storage_path = true,
    before_select = true,
}

local cache_keys = {
    max_buffers = true,
}

---@param opts Tracks.Opts|nil
---@return Tracks.Config
function M.normalize(opts)
    if opts == nil then opts = {} end
    expect_table(opts, "options")
    reject_unknown(opts, section_keys, "options")

    if opts.point_jump ~= nil then
        expect_table(opts.point_jump, "point_jump")
        reject_unknown(opts.point_jump, point_keys, "point_jump")
    end
    if opts.file_jump ~= nil then
        expect_table(opts.file_jump, "file_jump")
        reject_unknown(opts.file_jump, file_keys, "file_jump")
    end
    if opts.active ~= nil then
        expect_table(opts.active, "active")
        reject_unknown(opts.active, active_keys, "active")
    end
    if opts.buffer_cache ~= nil then
        expect_table(opts.buffer_cache, "buffer_cache")
        reject_unknown(opts.buffer_cache, cache_keys, "buffer_cache")
    end
    if opts.keymaps ~= nil and opts.keymaps ~= false then
        expect_table(opts.keymaps, "keymaps")
        reject_unknown(opts.keymaps, keymap_keys, "keymaps")
    end

    local normalized = vim.deepcopy(M.defaults)
    normalized.point_jump =
        vim.tbl_deep_extend("force", normalized.point_jump, opts.point_jump or {})
    normalized.file_jump = vim.tbl_extend("force", normalized.file_jump, opts.file_jump or {})
    normalized.active = vim.tbl_extend("force", normalized.active, opts.active or {})
    normalized.buffer_cache =
        vim.tbl_extend("force", normalized.buffer_cache, opts.buffer_cache or {})
    if opts.keymaps == false then
        normalized.keymaps = false
    elseif opts.keymaps ~= nil then
        normalized.keymaps = vim.tbl_extend("force", normalized.keymaps, opts.keymaps)
    end
    if normalized.keymaps then
        for name, lhs in pairs(normalized.keymaps) do
            if lhs ~= false and (type(lhs) ~= "string" or lhs == "") then
                invalid_type(("keymaps.%s"):format(name), "a non-empty string or false", lhs)
            end
        end
    end

    local point = normalized.point_jump
    expect_integer(point.debounce_ms, "point_jump.debounce_ms", 0)
    expect_integer(point.max_history, "point_jump.max_history", 1)
    expect_integer(point.min_block_lines, "point_jump.min_block_lines", 0)
    expect_integer(point.max_semantic_area_lines, "point_jump.max_semantic_area_lines", 1)
    expect_integer(point.locality_lines, "point_jump.locality_lines", 0)
    expect_integer(point.max_ts_field_len, "point_jump.max_ts_field_len", 1)
    expect_string_list(point.exclude_filetypes, "point_jump.exclude_filetypes")
    expect_table(point.capture_priority, "point_jump.capture_priority")
    for capture, priority in pairs(point.capture_priority) do
        if type(capture) ~= "string" then
            invalid_type("point_jump.capture_priority keys", "strings", capture)
        end
        if
            type(priority) ~= "number"
            or priority ~= priority
            or priority <= 0
            or priority == math.huge
        then
            error(
                ("tracks.setup(): point_jump.capture_priority.%s must be a positive finite number"):format(
                    capture
                ),
                0
            )
        end
    end

    local file = normalized.file_jump
    expect_integer(file.max_history, "file_jump.max_history", 1)
    expect_string_list(file.exclude_filetypes, "file_jump.exclude_filetypes")

    local active = normalized.active
    expect_integer(active.max_files, "active.max_files", 1)
    if type(active.storage_path) ~= "string" then
        invalid_type("active.storage_path", "a string", active.storage_path)
    end
    if active.storage_path == "" then
        error("tracks.setup(): active.storage_path must not be empty", 0)
    end
    active.storage_path = vim.fs.normalize(vim.fs.abspath(active.storage_path))
    if active.before_select ~= nil and type(active.before_select) ~= "function" then
        invalid_type("active.before_select", "a function or nil", active.before_select)
    end

    expect_integer(normalized.buffer_cache.max_buffers, "buffer_cache.max_buffers", 0)

    return normalized
end

return M
