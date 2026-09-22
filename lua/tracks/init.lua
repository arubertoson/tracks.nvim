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

local config = require("tracks.config")

local M = {}

local setup_state = "new"

M.point_jump = require("tracks.point_jump")
M.file_jump = require("tracks.file_jump")
M.active = require("tracks.active")
M.buffer_cache = require("tracks.buffer_cache")

---@param opts Tracks.Opts|nil
function M.setup(opts)
    if setup_state ~= "new" then
        error("tracks.setup() may only be called once; restart Neovim to reconfigure tracks", 2)
    end

    -- Validate the complete public boundary before activating any subsystem.
    local normalized = config.normalize(opts)

    setup_state = "initializing"
    local ok, err = xpcall(function()
        M.point_jump._setup(normalized.point_jump)
        M.file_jump._setup(normalized.file_jump)
        M.active._setup(normalized.active)
        M.buffer_cache._setup(
            normalized.buffer_cache,
            function(path) return M.active.contains(path) end
        )
    end, debug.traceback)

    if not ok then
        setup_state = "new"
        error(err, 0)
    end
    setup_state = "initialized"
end

return M
