pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            package.loaded["tracks.file_jump"] = nil
        end,
        post_case = function() vim.cmd("silent! %bwipeout!") end,
    },
})

local function file_jump() return require("tracks.file_jump") end

---@param name string
---@param listed boolean?
---@return number
local function named_buffer(name, listed)
    local bufnr = vim.api.nvim_create_buf(listed ~= false, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(vim.fn.tempname(), name))
    return bufnr
end

T["trackable buffers"] = MiniTest.new_set()

T["trackable buffers"]["accepts listed normal file buffers"] = function()
    local bufnr = named_buffer("file.lua")
    MiniTest.expect.no_equality(file_jump()._test.trackable_path(bufnr), nil)
end

T["trackable buffers"]["rejects unnamed buffers but accepts unlisted files"] = function()
    local unnamed = vim.api.nvim_create_buf(true, false)
    local unlisted = named_buffer("unlisted.lua", false)

    MiniTest.expect.equality(file_jump()._test.trackable_path(unnamed), nil)
    MiniTest.expect.no_equality(file_jump()._test.trackable_path(unlisted), nil)
end

T["trackable buffers"]["rejects every non-normal buftype"] = function()
    for _, buftype in ipairs({ "nofile", "nowrite", "acwrite", "quickfix", "help", "prompt" }) do
        local bufnr = named_buffer("special-" .. buftype)
        vim.api.nvim_set_option_value("buftype", buftype, { buf = bufnr })
        MiniTest.expect.equality(file_jump()._test.trackable_path(bufnr), nil)
    end
end

T["trackable buffers"]["rejects shared plugin UI filetypes"] = function()
    local filetypes = {
        "fff_input",
        "fff_list",
        "fff_preview",
        "minipick",
        "mininotify",
        "no-neck-pain",
        "oil",
        "oil_progress",
    }

    for _, filetype in ipairs(filetypes) do
        local bufnr = named_buffer("ui-" .. filetype)
        vim.api.nvim_set_option_value("filetype", filetype, { buf = bufnr })
        MiniTest.expect.equality(file_jump()._test.trackable_path(bufnr), nil)
    end
end

T["trackable buffers"]["rejects quick-close views and URI buffers"] = function()
    local quick_close = named_buffer("health")
    vim.api.nvim_set_option_value("filetype", "checkhealth", { buf = quick_close })

    local uri = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(uri, "gitsigns://revision/file.lua")

    MiniTest.expect.equality(file_jump()._test.trackable_path(quick_close), nil)
    MiniTest.expect.equality(file_jump()._test.trackable_path(uri), nil)
end

T["portable visits"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local a = vim.fs.joinpath(root, "a.lua")
    local b = vim.fs.joinpath(root, "b.lua")
    vim.fn.writefile({ "a", "second" }, a)
    vim.fn.writefile({ "b", "second" }, b)

    vim.cmd.edit(vim.fn.fnameescape(a))
    local jump = file_jump()
    jump._setup(require("tracks.config").defaults.file_jump)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd.edit(vim.fn.fnameescape(b))
    local snapshot = jump.snapshot()
    MiniTest.expect.equality(#snapshot.entries, 2)
    MiniTest.expect.equality(snapshot.entries[1].view.lnum, 2)

    jump.import(snapshot)
    MiniTest.expect.equality(#jump.history.entries, 2)
    vim.cmd.edit(vim.fn.fnameescape(a))
    MiniTest.expect.equality(#jump.history.entries, 3)
    MiniTest.expect.equality(jump.prev(), true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), b)
    vim.cmd.edit(vim.fn.fnameescape(b))
    jump.import(snapshot)
    MiniTest.expect.equality(#jump.history.entries, 2)
end

T["navigation"] = MiniTest.new_set()

T["navigation"]["skips missing files"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")

    local paths = {}
    for _, name in ipairs({ "a", "b", "c" }) do
        paths[name] = vim.fs.joinpath(root, name .. ".lua")
        vim.fn.writefile({ name }, paths[name])
    end

    vim.cmd.edit(vim.fn.fnameescape(paths.c))
    local jump = file_jump()
    local view = vim.fn.winsaveview()
    jump.history = {
        entries = {
            { path = vim.fs.normalize(paths.a), view = view },
            { path = vim.fs.normalize(paths.b), view = view },
            { path = vim.fs.normalize(paths.c), view = view },
        },
        index = 3,
        alternate_index = 2,
    }

    vim.uv.fs_unlink(paths.b)

    MiniTest.expect.equality(jump.prev(), true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), vim.fs.normalize(paths.a))
    MiniTest.expect.equality(#jump.history.entries, 2)
    MiniTest.expect.equality(jump.history.index, 1)
end

return T
