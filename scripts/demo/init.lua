local source = assert(debug.getinfo(1, "S").source):gsub("^@", "")
local init_path = vim.fn.fnamemodify(source, ":p")
local root = vim.fn.fnamemodify(init_path, ":h:h:h")
local active_store = vim.fn.tempname() .. "-tracks-demo-active.json"

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(root, "scripts", "demo", "runtime"))
vim.cmd.cd(vim.fn.fnameescape(root))

vim.g.mapleader = " "
vim.opt.background = "dark"
vim.opt.cmdheight = 1
vim.opt.cursorline = true
vim.opt.laststatus = 2
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.ruler = false
vim.opt.showmode = false
vim.opt.signcolumn = "no"
vim.opt.termguicolors = true
vim.opt.wrap = false

pcall(vim.cmd.colorscheme, "habamax")

local tracks = require("tracks")
tracks.setup({
    active = {
        storage_path = active_store,
    },
    buffer_cache = {
        max_buffers = 3,
    },
})

vim.g.tracks_demo_message = "Visit files to build a chronological trail"

local function filename() return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") end

local function set_message(message)
    vim.g.tracks_demo_message = message
    vim.cmd.redrawstatus()
end

_G.TracksDemoHeader = function() return " tracks.nvim  ·  " .. vim.g.tracks_demo_message end

_G.TracksDemoStatus = function()
    local slots = {}
    for index, item in ipairs(tracks.active.items()) do
        slots[#slots + 1] = ("%d:%s"):format(index, vim.fn.fnamemodify(item.path, ":t"))
    end

    local active = #slots > 0 and table.concat(slots, "  ") or "none"
    return (" %%f%%m%%= ACTIVE  %s "):format(active)
end

vim.opt.winbar = "%{%v:lua.TracksDemoHeader()%}"
vim.opt.statusline = "%{%v:lua.TracksDemoStatus()%}"

vim.keymap.set("n", "K", function()
    tracks.point_jump.prev()
    set_message("Semantic history ← returned to the previous function landing")
end, { desc = "Demo: previous semantic point" })

vim.keymap.set("n", "J", function()
    tracks.point_jump.next()
    set_message("Semantic history → returned to the next function landing")
end, { desc = "Demo: next semantic point" })

vim.keymap.set("n", "ga", function()
    if tracks.active.add() then
        set_message("Pinned " .. filename() .. " to the active working set")
    else
        set_message(filename() .. " is already active")
    end
end, { desc = "Demo: add active file" })

vim.keymap.set("n", "H", function()
    if tracks.file_jump.prev() then
        set_message("File history ← restored " .. filename() .. " and its view")
    else
        set_message("Already at the oldest file visit")
    end
end, { desc = "Demo: previous file visit" })

vim.keymap.set("n", "L", function()
    if tracks.file_jump.next() then
        set_message("File history → restored " .. filename() .. " and its view")
    else
        set_message("Already at the newest file visit")
    end
end, { desc = "Demo: next file visit" })

vim.keymap.set("n", "gs", function()
    if tracks.active.select(1) then
        set_message("Selected active slot 1 → " .. filename())
    else
        set_message("Active slot 1 is empty")
    end
end, { desc = "Demo: select first active file" })

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        vim.uv.fs_unlink(active_store)
        vim.uv.fs_rmdir(active_store .. ".lock")
    end,
})
