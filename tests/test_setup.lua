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
local keymap_calls
local original_keymap_set

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            setup_calls = 0
            keymap_calls = {}
            original_keymap_set = vim.keymap.set
            vim.keymap.set = function(mode, lhs, rhs, opts)
                keymap_calls[#keymap_calls + 1] =
                    { mode = mode, lhs = lhs, rhs = rhs, opts = opts }
            end
            package.loaded.tracks = nil
            for _, name in ipairs(leaf_modules) do
                originals[name] = package.loaded[name]
                package.loaded[name] = {
                    _setup = function() setup_calls = setup_calls + 1 end,
                    contains = function() return false end,
                }
            end
        end,
        post_case = function()
            vim.keymap.set = original_keymap_set
            package.loaded.tracks = nil
            for _, name in ipairs(leaf_modules) do
                package.loaded[name] = originals[name]
            end
        end,
    },
})

T["setup installs navigation keymaps by default"] = function()
    local tracks = require("tracks")
    tracks.setup()

    MiniTest.expect.equality(#keymap_calls, 5)
    MiniTest.expect.equality(keymap_calls[1].lhs, "<M-h>")
    MiniTest.expect.equality(keymap_calls[1].rhs, tracks.file_jump.prev)
    MiniTest.expect.equality(keymap_calls[2].lhs, "<M-l>")
    MiniTest.expect.equality(keymap_calls[3].lhs, "<M-k>")
    MiniTest.expect.equality(keymap_calls[4].lhs, "<M-j>")
    MiniTest.expect.equality(keymap_calls[5].lhs, "<M-t>")
end

T["setup overrides or disables individual default keys"] = function()
    local tracks = require("tracks")
    tracks.setup({ keymaps = { file_prev = "<C-h>", point_next = false } })

    MiniTest.expect.equality(#keymap_calls, 4)
    MiniTest.expect.equality(keymap_calls[1].lhs, "<C-h>")
    MiniTest.expect.equality(keymap_calls[1].rhs, tracks.file_jump.prev)
    MiniTest.expect.equality(keymap_calls[4].lhs, "<M-t>")
end

T["setup can skip keymaps"] = function()
    require("tracks").setup({ keymaps = false })

    MiniTest.expect.equality(#keymap_calls, 0)
end

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
    tracks.point_jump._setup = function()
        attempts = attempts + 1
        if attempts == 1 then error("initialization failed") end
    end

    MiniTest.expect.equality(pcall(tracks.setup), false)
    MiniTest.expect.equality(pcall(tracks.setup), true)
    MiniTest.expect.equality(attempts, 2)
end

T["setup validates all options before activation"] = function()
    local tracks = require("tracks")

    local type_ok, type_err = pcall(tracks.setup, false)
    MiniTest.expect.equality(type_ok, false)
    MiniTest.expect.equality(type_err:find("options must be a table", 1, true) ~= nil, true)

    local key_ok, key_err = pcall(tracks.setup, {
        point_jump = { debounce_ms = "fast" },
        unknown = true,
    })
    MiniTest.expect.equality(key_ok, false)
    MiniTest.expect.equality(key_err:find("unknown option options.unknown", 1, true) ~= nil, true)

    MiniTest.expect.equality(setup_calls, 0)
    MiniTest.expect.equality(pcall(tracks.setup), true)
end

T["setup rejects invalid nested values"] = function()
    local tracks = require("tracks")
    local cases = {
        {
            opts = { point_jump = { augroup_id = 1 } },
            message = "unknown option point_jump.augroup_id",
        },
        {
            opts = { file_jump = { max_history = 0 } },
            message = "file_jump.max_history must be at least 1",
        },
        {
            opts = { active = { before_select = true } },
            message = "active.before_select",
        },
        {
            opts = { buffer_cache = { max_buffers = "eight" } },
            message = "buffer_cache.max_buffers",
        },
    }

    for _, case in ipairs(cases) do
        local ok, err = pcall(tracks.setup, case.opts)
        MiniTest.expect.equality(ok, false)
        MiniTest.expect.equality(err:find(case.message, 1, true) ~= nil, true)
    end
    MiniTest.expect.equality(setup_calls, 0)
    MiniTest.expect.equality(pcall(tracks.setup), true)
end

return T
