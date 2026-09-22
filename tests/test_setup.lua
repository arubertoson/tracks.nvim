pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local leaf_modules = {
    "tracks.point_jump",
    "tracks.file_jump",
    "tracks.active",
    "tracks.buffer_cache",
}

local originals = {}
local setup_calls

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            setup_calls = 0
            package.loaded.tracks = nil
            for _, name in ipairs(leaf_modules) do
                originals[name] = package.loaded[name]
                package.loaded[name] = {
                    setup = function() setup_calls = setup_calls + 1 end,
                    contains = function() return false end,
                }
            end
        end,
        post_case = function()
            package.loaded.tracks = nil
            for _, name in ipairs(leaf_modules) do
                package.loaded[name] = originals[name]
            end
        end,
    },
})

T["setup rejects a second call"] = function()
    local tracks = require("tracks")
    tracks.setup()

    local ok, err = pcall(tracks.setup)

    MiniTest.expect.equality(ok, false)
    MiniTest.expect.equality(err:find("may only be called once", 1, true) ~= nil, true)
    MiniTest.expect.equality(setup_calls, 4)
end

T["setup can be retried after initialization fails"] = function()
    local tracks = require("tracks")
    local attempts = 0
    tracks.point_jump.setup = function()
        attempts = attempts + 1
        if attempts == 1 then error("initialization failed") end
    end

    MiniTest.expect.equality(pcall(tracks.setup), false)
    MiniTest.expect.equality(pcall(tracks.setup), true)
    MiniTest.expect.equality(attempts, 2)
end

return T
