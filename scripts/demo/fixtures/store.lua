local M = {}
local tracks = {}

local function index_of(candidate)
    for index, track in ipairs(tracks) do
        if track.path == candidate.path then return index end
    end
end

function M.insert(track)
    if index_of(track) then return false end

    tracks[#tracks + 1] = track
    return true
end

function M.save(track)
    local index = index_of(track)
    if not index then return false end

    tracks[index] = vim.deepcopy(track)
    return true
end

function M.all() return vim.deepcopy(tracks) end

return M
