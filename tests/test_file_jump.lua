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

return T
