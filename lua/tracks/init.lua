---@module "tracks"
---@brief Navigation entry point.
---
--- Navigation is split into focused subsystems:
--- - point_jump: semantic point history within a buffer
--- - file_jump: automatic, restorable file-visit history
--- - active: small persisted working set of pinned files
--- - buffer_cache: MRU loaded-buffer cache and pruning policy
---
--- This module wires those pieces together so the leaf modules can stay
--- independent of each other.

local M = {}

local setup_state = "new"

M.point_jump = require("tracks.point_jump")
M.file_jump = require("tracks.file_jump")
M.active = require("tracks.active")
M.buffer_cache = require("tracks.buffer_cache")

---@class Tracks.Opts
---@field point_jump Tracks.PointJumpConfig|nil
---@field file_jump Tracks.FileJumpConfig|nil
---@field active Tracks.ActiveConfig|nil
---@field buffer_cache Tracks.BufferCacheConfig|nil

---@param opts Tracks.Opts|nil
function M.setup(opts)
    if setup_state ~= "new" then
        error("tracks.setup() may only be called once; restart Neovim to reconfigure tracks", 2)
    end

    setup_state = "initializing"
    local ok, err = xpcall(function()
        opts = opts or {}
        M.point_jump.setup(opts.point_jump)
        M.file_jump.setup(opts.file_jump)
        M.active.setup(opts.active)

        local cache_opts = vim.tbl_extend("force", opts.buffer_cache or {}, {
            is_pinned = function(path) return M.active.contains(path) end,
        })
        M.buffer_cache.setup(cache_opts)
    end, debug.traceback)

    if not ok then
        setup_state = "new"
        error(err, 0)
    end
    setup_state = "initialized"
end

return M
