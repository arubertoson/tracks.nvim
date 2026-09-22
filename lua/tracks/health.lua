---@module "tracks.health"
---Environment diagnostics for tracks.nvim.

local config = require("tracks.config")
local scope = require("tracks.scope")

local M = {}

local health = vim.health

---@param path string
---@return string?
local function existing_ancestor(path)
    local current = vim.fs.dirname(path)
    while current and current ~= "" do
        local stat = vim.uv.fs_stat(current)
        if stat then return stat.type == "directory" and current or nil end

        local parent = vim.fs.dirname(current)
        if parent == current then return nil end
        current = parent
    end
    return nil
end

local function check_version()
    health.start("tracks.nvim")
    if vim.fn.has("nvim-0.13") == 1 then
        health.ok("Neovim 0.13 or newer")
    else
        health.error("Neovim 0.13 or newer is required")
    end
end

local function check_treesitter()
    health.start("Treesitter semantic points")

    local bufnr = vim.api.nvim_get_current_buf()
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if filetype == "" then
        health.info(
            "Current buffer has no filetype; parser and textobject queries were not checked"
        )
        return
    end

    local lang = vim.treesitter.language.get_lang(filetype)
    if not lang then
        health.warn(("No Treesitter language is registered for filetype %q"):format(filetype))
        return
    end

    local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not parser_ok or not parser then
        health.warn(("No Treesitter parser is available for %q"):format(lang))
        return
    end
    health.ok(("Treesitter parser available for %q"):format(lang))

    local query_ok, query = pcall(vim.treesitter.query.get, lang, "textobjects")
    if not query_ok or not query then
        health.warn(("No textobjects query is available for %q"):format(lang))
        return
    end

    local point_module = package.loaded["tracks.point_jump"]
    local point_config = point_module and point_module.config or config.defaults.point_jump
    local configured = {}
    for capture in pairs(point_config.capture_priority) do
        configured[capture] = true
    end

    local found = {}
    for _, capture in ipairs(query.captures) do
        if configured[capture] then found[capture] = true end
    end

    local captures = vim.tbl_keys(found)
    table.sort(captures)
    if #captures == 0 then
        health.warn("The textobjects query has none of the configured semantic captures")
    else
        health.ok("Configured semantic captures: " .. table.concat(captures, ", "))
    end
end

local function check_storage()
    health.start("Active-file storage")

    local active_module = package.loaded["tracks.active"]
    local active_config = active_module and active_module.config or config.defaults.active
    local path = active_config.storage_path
    local stat = vim.uv.fs_stat(path)

    if stat and stat.type ~= "file" then
        health.error("Active-file storage is not a regular file: " .. path)
        return
    end

    if stat then
        local readable, lines = pcall(vim.fn.readfile, path)
        local decoded_ok, decoded = false, nil
        if readable then
            decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
        end

        if not readable or not decoded_ok or type(decoded) ~= "table" then
            health.error("Active-file storage does not contain a valid JSON object: " .. path)
        else
            health.ok("Active-file storage is readable: " .. path)
        end

        if vim.fn.filewritable(path) == 1 then
            health.ok("Active-file storage is writable")
        else
            health.error("Active-file storage is not writable: " .. path)
        end
        return
    end

    local parent = existing_ancestor(path)
    if parent and vim.fn.filewritable(parent) == 2 then
        health.ok("Active-file storage can be created under: " .. parent)
    else
        health.error("No writable parent exists for active-file storage: " .. path)
    end
end

local function check_scope()
    health.start("Project scope")

    local source = vim.api.nvim_buf_get_name(0)
    if source == "" then source = vim.uv.cwd() or "" end

    local git_root = source ~= "" and vim.fs.root(source, { ".git" }) or nil
    local active_scope = scope.for_source(source)
    if git_root and active_scope then
        health.ok(("Git scope: %s (%s)"):format(active_scope.root, active_scope.branch))
    elseif active_scope then
        health.info("No Git worktree detected; active files use cwd scope: " .. active_scope.root)
    else
        health.warn("No project scope could be determined")
    end
end

function M.check()
    check_version()
    check_treesitter()
    check_storage()
    check_scope()
end

return M
