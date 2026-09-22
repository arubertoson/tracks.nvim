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
    opts = opts or {}
    M.point_jump.setup(opts.point_jump)
    M.file_jump.setup(opts.file_jump)
    M.active.setup(opts.active)

    local cache_opts = vim.tbl_extend("force", opts.buffer_cache or {}, {
        is_pinned = function(path) return M.active.contains(path) end,
    })
    M.buffer_cache.setup(cache_opts)
end

return M
