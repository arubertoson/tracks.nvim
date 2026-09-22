local store = require("store")

local M = {}

local function normalize_name(name) return vim.trim(name):lower() end

function M.create_track(name, path)
    local track = {
        name = normalize_name(name),
        path = vim.fs.normalize(path),
        played = 0,
    }

    store.insert(track)
    return track
end

function M.play(track)
    track.played = track.played + 1
    store.save(track)

    return ("playing %s"):format(track.name)
end

return M
