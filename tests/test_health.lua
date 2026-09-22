pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local original_health
local original_active
local reports

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            reports = {}
            original_health = vim.health
            original_active = package.loaded["tracks.active"]
            package.loaded["tracks.health"] = nil
            vim.health = {}
            for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
                vim.health[level] = function(message)
                    reports[#reports + 1] = { level = level, message = message }
                end
            end
        end,
        post_case = function()
            vim.health = original_health
            package.loaded["tracks.active"] = original_active
            package.loaded["tracks.health"] = nil
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local function report_contains(level, text)
    for _, report in ipairs(reports) do
        if report.level == level and report.message:find(text, 1, true) then return true end
    end
    return false
end

T["health checks supported runtime dependencies"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local source = vim.fs.joinpath(root, "health.lua")
    local storage = vim.fs.joinpath(root, "active.json")
    vim.fn.writefile({ "local function healthy()", "  return true", "end" }, source)
    vim.fn.writefile({ "{}" }, storage)
    package.loaded["tracks.active"] = { config = { storage_path = storage } }

    vim.cmd.edit(vim.fn.fnameescape(source))
    vim.bo.filetype = "lua"
    require("tracks.health").check()

    MiniTest.expect.equality(report_contains("ok", "Neovim 0.13 or newer"), true)
    MiniTest.expect.equality(report_contains("ok", "Treesitter parser available"), true)
    MiniTest.expect.equality(report_contains("ok", "Configured semantic captures"), true)
    MiniTest.expect.equality(report_contains("ok", "Active-file storage is readable"), true)
    MiniTest.expect.equality(report_contains("error", ""), false)
end

return T
