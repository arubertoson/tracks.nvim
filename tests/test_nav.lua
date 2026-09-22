pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            package.loaded["tracks.active"] = nil
            package.loaded["tracks.buffer_cache"] = nil
        end,
        post_case = function() vim.cmd("silent! %bwipeout!") end,
    },
})

local tmp_root = vim.fn.tempname()
vim.fn.mkdir(tmp_root, "p")

local function temp_project(name, branch)
    local root = tmp_root .. "/" .. name
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.writefile({ "ref: refs/heads/" .. (branch or "main") }, root .. "/.git/HEAD")
    return root
end

local function temp_file(root, name)
    local path = root .. "/" .. name
    vim.fn.writefile({ name }, path)
    return path
end

local function edit(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end

local function setup_active(storage)
    local active = require("tracks.active")
    active.setup({ storage_path = storage })
    return active
end

T["active files"] = MiniTest.new_set()

T["active files"]["compacts on removal"] = function()
    local root = temp_project("active-compact", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    active.add()

    active.remove(1)

    MiniTest.expect.equality(#active.items(), 1)
    MiniTest.expect.equality(active.items()[1].path, vim.fs.normalize(b))
end

T["active files"]["does not grow past max files"] = function()
    local root = temp_project("active-max", "main")
    local storage = root .. "/active.json"
    local active

    for i = 1, 4 do
        edit(temp_file(root, ("%d.lua"):format(i)))
        active = active or setup_active(storage)
        active.add()
    end

    MiniTest.expect.equality(#active.items(), 3)
end

T["active files"]["remove all clears current scope"] = function()
    local root = temp_project("active-remove-all", "main")
    local storage = root .. "/active.json"

    edit(temp_file(root, "a.lua"))
    local active = setup_active(storage)
    active.add()

    edit(temp_file(root, "b.lua"))
    active.add()

    MiniTest.expect.equality(active.remove_all(), 2)
    MiniTest.expect.equality(#active.items(), 0)
end

T["active files"]["replace updates explicit slot"] = function()
    local root = temp_project("active-replace", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")
    local c = temp_file(root, "c.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    active.add()

    edit(c)
    MiniTest.expect.equality(active.replace(1), true)

    local items = active.items()
    MiniTest.expect.equality(#items, 2)
    MiniTest.expect.equality(items[1].path, vim.fs.normalize(c))
    MiniTest.expect.equality(items[2].path, vim.fs.normalize(b))
end

T["active files"]["replace can fill next empty slot"] = function()
    local root = temp_project("active-replace-empty", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    MiniTest.expect.equality(active.replace(2), true)
    MiniTest.expect.equality(active.replace(3), false)

    MiniTest.expect.equality(#active.items(), 2)
    MiniTest.expect.equality(active.items()[2].path, vim.fs.normalize(b))
end

T["active files"]["replace rejects duplicate active files"] = function()
    local root = temp_project("active-replace-duplicate", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    active.add()

    edit(a)
    MiniTest.expect.equality(active.replace(2), false)
    MiniTest.expect.equality(active.items()[2].path, vim.fs.normalize(b))
end

T["active files"]["remove does not delete buffers"] = function()
    local root = temp_project("active-buffer-cleanup", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    local buf_a = edit(a)
    local active = setup_active(storage)
    active.add()

    edit(b)
    active.remove(1)

    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_a), true)
end

T["active files"]["replaces existing persisted state"] = function()
    local root = temp_project("active-replace-persisted", "main")
    local storage = root .. "/active.json"
    local stale = temp_file(root, "stale.lua")
    local current = temp_file(root, "current.lua")
    local normalized_root = vim.fs.normalize(root)

    vim.fn.writefile(
        { vim.json.encode({ [normalized_root] = { main = { "stale.lua" } } }) },
        storage
    )

    edit(current)
    local active = setup_active(storage)
    MiniTest.expect.equality(active.items()[1].path, vim.fs.normalize(stale))
    MiniTest.expect.equality(active.replace(1), true)

    local decoded = vim.json.decode(table.concat(vim.fn.readfile(storage), "\n"))
    MiniTest.expect.equality(decoded[normalized_root].main, { "current.lua" })
end

T["active files"]["persists by root and branch"] = function()
    local root = temp_project("active-scope", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")

    edit(a)
    local active = setup_active(storage)
    active.add()
    MiniTest.expect.equality(#active.items(), 1)

    local decoded = vim.json.decode(table.concat(vim.fn.readfile(storage), "\n"))
    MiniTest.expect.equality(decoded[vim.fs.normalize(root)].main[1], "a.lua")

    package.loaded["tracks.active"] = nil
    active = setup_active(storage)
    MiniTest.expect.equality(#active.items(), 1)

    vim.fn.writefile({ "ref: refs/heads/feature" }, root .. "/.git/HEAD")
    package.loaded["tracks.active"] = nil
    active = setup_active(storage)
    MiniTest.expect.equality(#active.items(), 0)
end

T["buffer cache"] = MiniTest.new_set()

T["buffer cache"]["adopts buffers loaded before setup"] = function()
    local root = temp_project("buffers-adopt", "main")
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")
    local c = temp_file(root, "c.lua")

    local buf_a = edit(a)
    local buf_b = edit(b)
    edit(c)

    local buffers = require("tracks.buffer_cache")
    buffers.setup({ max_buffers = 2 })
    buffers.prune()

    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_a), false)
    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_b), true)
end

T["buffer cache"]["tracks buffers loaded without entering them"] = function()
    local root = temp_project("buffers-background-load", "main")
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    edit(a)
    local buffers = require("tracks.buffer_cache")
    buffers.setup()

    local buf_b = vim.fn.bufadd(b)
    vim.fn.bufload(buf_b)

    MiniTest.expect.equality(vim.tbl_contains(buffers.tracked(), vim.fs.normalize(b)), true)
end

T["buffer cache"]["forgets unloaded buffers"] = function()
    local root = temp_project("buffers-unload", "main")
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    local buf_a = edit(a)
    local buffers = require("tracks.buffer_cache")
    buffers.setup()
    edit(b)

    vim.cmd("bunload " .. buf_a)

    MiniTest.expect.equality(vim.tbl_contains(buffers.tracked(), vim.fs.normalize(a)), false)
end

T["buffer cache"]["prunes cold unpinned file buffers"] = function()
    local root = temp_project("buffers-prune", "main")
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")
    local c = temp_file(root, "c.lua")

    local buf_a = edit(a)
    local buffers = require("tracks.buffer_cache")
    buffers.setup({
        max_buffers = 2,
        is_pinned = function(path) return path == vim.fs.normalize(a) end,
    })

    local buf_b = edit(b)
    edit(c)
    buffers.prune()

    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_a), true)
    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_b), false)
end

T["buffer cache"]["prunes when active pins change"] = function()
    local root = temp_project("buffers-active-update", "main")
    local storage = root .. "/active.json"
    local a = temp_file(root, "a.lua")
    local b = temp_file(root, "b.lua")

    local buf_a = edit(a)
    local active = setup_active(storage)
    active.add()

    local buffers = require("tracks.buffer_cache")
    buffers.setup({
        max_buffers = 1,
        is_pinned = function(path) return active.contains(path) end,
    })

    edit(b)
    active.remove(1)

    vim.wait(1000, function() return not vim.api.nvim_buf_is_loaded(buf_a) end)
    MiniTest.expect.equality(vim.api.nvim_buf_is_loaded(buf_a), false)
end

return T
