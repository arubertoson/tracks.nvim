pcall(vim.cmd, "packadd mini.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local config = require("tracks.config")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            vim.cmd("silent! %bwipeout!")
            package.loaded["tracks.point_jump"] = nil
        end,
        post_case = function()
            local ok, jump = pcall(require, "tracks.point_jump")
            if ok then pcall(jump.reset) end
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

local tmp_root = vim.fn.tempname()
vim.fn.mkdir(tmp_root, "p")

local function temp_file(name, line_count)
    local path = vim.fs.joinpath(tmp_root, name)
    local lines = {}
    for line = 1, line_count do
        lines[line] = ("line %03d"):format(line)
    end
    vim.fn.writefile(lines, path)
    return path
end

local function setup_jump(path, opts)
    vim.cmd.edit(vim.fn.fnameescape(path))
    local jump = require("tracks.point_jump")
    jump._setup(config.normalize({ point_jump = opts }).point_jump)
    return jump, jump.buffers[vim.fs.normalize(path)]
end

local function view_at(line)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

local function semantic_at(line)
    return {
        capture = "function.outer",
        kind = "function",
        name = "point_" .. line,
        start_row = line - 1,
        start_col = 0,
        end_row = line,
        end_col = 0,
    }
end

local function entry_at(jump, state, line)
    local view = view_at(line)
    local entry = {
        anchor_view = vim.deepcopy(view),
        target_view = vim.deepcopy(view),
        semantic = semantic_at(line),
    }
    state.session.extmarks[entry] = {
        anchor = vim.api.nvim_buf_set_extmark(
            state.session.bufnr,
            jump._test.namespace,
            line - 1,
            0,
            {}
        ),
        target = vim.api.nvim_buf_set_extmark(
            state.session.bufnr,
            jump._test.namespace,
            line - 1,
            0,
            {}
        ),
    }
    return entry
end

T["semantic-only history"] = MiniTest.new_set()

T["semantic-only history"]["does not record locations outside semantic areas"] = function()
    local path = temp_file("outside.txt", 100)
    local jump, state = setup_jump(path)

    jump._test.record_point(state, state.session, view_at(70))

    MiniTest.expect.equality(#state.history.entries, 0)
    MiniTest.expect.equality(state.history.index, 0)
end

T["semantic-only history"]["previous from an ignored location restores latest point"] = function()
    local path = temp_file("outside-prev.txt", 120)
    local jump, state = setup_jump(path)

    state.history.entries = { entry_at(jump, state, 20), entry_at(jump, state, 60) }
    state.history.index = 2
    view_at(100)

    jump.prev()

    MiniTest.expect.equality(vim.fn.line("."), 60)
    MiniTest.expect.equality(state.history.index, 2)
end

T["semantic ownership"] = MiniTest.new_set()

T["semantic ownership"]["does not transfer a deleted owner to an adjacent function"] = function()
    local path = vim.fs.joinpath(tmp_root, "deleted-owner.lua")
    vim.fn.writefile({
        "local function alpha()",
        "  return 1",
        "end",
        "",
        "local function beta()",
        "  return 2",
        "end",
        "",
        "",
    }, path)

    local jump, state = setup_jump(path, { debounce_ms = 100000 })
    vim.bo.filetype = "lua"

    jump._test.record_point(state, state.session, view_at(2))
    MiniTest.expect.equality(state.history.entries[1].semantic.name, "alpha")

    vim.api.nvim_buf_set_lines(0, 0, 4, false, {})
    jump._test.record_point(state, state.session, view_at(5))

    MiniTest.expect.equality(#state.history.entries, 0)
end

T["semantic cache"] = MiniTest.new_set()

T["semantic cache"]["reuses captures until the buffer changes"] = function()
    local path = vim.fs.joinpath(tmp_root, "semantic-cache.lua")
    vim.fn.writefile({
        "local function alpha()",
        "  return 1",
        "end",
        "",
    }, path)

    local jump, state = setup_jump(path, { debounce_ms = 100000 })
    vim.bo.filetype = "lua"

    jump._test.record_point(state, state.session, view_at(2))
    local first_cache = state.session.semantic_cache
    MiniTest.expect.no_equality(first_cache, nil)

    jump._test.record_point(state, state.session, view_at(2))
    MiniTest.expect.equality(state.session.semantic_cache == first_cache, true)

    vim.api.nvim_buf_set_lines(0, 3, 3, false, { "" })
    jump._test.record_point(state, state.session, view_at(2))

    MiniTest.expect.equality(state.session.semantic_cache == first_cache, false)
    MiniTest.expect.equality(
        state.session.semantic_cache.changetick,
        vim.api.nvim_buf_get_changedtick(0)
    )
end

return T
