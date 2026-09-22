---@module "tracks.point_jump"
---@brief Buffer-local semantic jump history.
---
--- A point belongs to a Treesitter-backed editing area when possible. Small
--- semantic nodes own one point; large nodes may own several bounded local
--- areas. Each entry has a fixed area anchor and a mutable return target, so
--- revisiting an area updates its landing position without allowing the area
--- itself to drift through the buffer.

local buf = require("tracks.buffer")
local ts = require("tracks.treesitter")

local M = {}

---@class Tracks.PointJumpConfig
---@field debounce_ms number
---@field max_history number
---@field min_block_lines number
---@field max_semantic_area_lines number
---@field locality_lines number
---@field max_ts_field_len number
---@field capture_priority table<string, number>
---@field exclude_filetypes string[]
---@field augroup_id number?
---@field namespace number
local default_config = {
    debounce_ms = 250,
    max_history = 10,
    min_block_lines = 12,
    max_semantic_area_lines = 30,
    locality_lines = 20,
    max_ts_field_len = 32,
    capture_priority = {
        ["block.outer"] = 1,
        ["function.outer"] = 2,
        ["method.outer"] = 2,
        ["class.outer"] = 3,
    },
    -- Additional filetypes excluded from this history.
    exclude_filetypes = {},
    augroup_id = nil,
    namespace = vim.api.nvim_create_namespace("tracks_point_jump"),
}

---@type Tracks.PointJumpConfig
M.config = vim.deepcopy(default_config)

---@class Tracks.PointView : vim.fn.winrestview.dict
---@field lnum number
---@field col number
---@field botline number

---@class Tracks.PointSemanticArea
---@field capture string
---@field kind string
---@field name string?
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class Tracks.PointEntry
---@field anchor_view Tracks.PointView
---@field target_view Tracks.PointView
---@field semantic Tracks.PointSemanticArea

---@class Tracks.PointHistory
---@field index number
---@field entries Tracks.PointEntry[]

---@class Tracks.PointEntryExtmarks
---@field anchor number
---@field target number

---@class Tracks.PointCursorPosition
---@field lnum number
---@field col number

---@class Tracks.PointSemanticCache
---@field changetick number
---@field filetype string
---@field config_generation number
---@field areas Tracks.PointSemanticArea[]

---@class Tracks.PointSession
---@field bufnr number
---@field changetick number
---@field debounce uv.uv_timer_t
---@field extmarks table<Tracks.PointEntry, Tracks.PointEntryExtmarks>
---@field ignore_cursor Tracks.PointCursorPosition?
---@field semantic_cache Tracks.PointSemanticCache?

---@class Tracks.PointBufferState
---@field history Tracks.PointHistory
---@field session Tracks.PointSession?

---@type table<string, Tracks.PointBufferState>
M.buffers = {}

local semantic_config_generation = 0

---@param view Tracks.PointView
---@return Tracks.PointView
local function copy_view(view) return vim.tbl_extend("force", {}, view) end

---@return Tracks.PointView
local function capture_view()
    return vim.tbl_extend("force", {}, vim.fn.winsaveview(), { botline = vim.fn.line("w$") })
end

---@param bufnr number
---@return string?
local function trackable_path(bufnr)
    if not buf.is_loaded(bufnr) then return nil end

    local path = buf.normal_file_path(bufnr)
    if not path then return nil end

    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.tbl_contains(M.config.exclude_filetypes, filetype) then return nil end

    return path
end

---@param semantic Tracks.PointSemanticArea
---@param row number
---@param col number
---@return boolean
local function semantic_contains(semantic, row, col)
    if row < semantic.start_row or row > semantic.end_row then return false end
    if row == semantic.start_row and col < semantic.start_col then return false end

    -- Treesitter ranges are end-exclusive.
    if row == semantic.end_row and col >= semantic.end_col then return false end

    return true
end

---@param semantic Tracks.PointSemanticArea
---@return number
local function semantic_line_count(semantic)
    local count = semantic.end_row - semantic.start_row
    if semantic.end_col > 0 then count = count + 1 end
    return math.max(count, 1)
end

---@param session Tracks.PointSession
---@return Tracks.PointSemanticArea[]?
local function semantic_areas(session)
    local bufnr = session.bufnr
    local changetick = vim.api.nvim_buf_get_changedtick(bufnr)
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    local cache = session.semantic_cache
    if
        cache
        and cache.changetick == changetick
        and cache.filetype == filetype
        and cache.config_generation == semantic_config_generation
    then
        return cache.areas
    end

    local iterator = ts.iter_textobj_captures(bufnr)
    if not iterator then return nil end

    local areas = {}
    for id, node in iterator.iter do
        local capture = iterator.query.captures[id]
        if not M.config.capture_priority[capture] then goto continue end

        local sr, sc, er, ec = node:range()
        local semantic = {
            capture = capture,
            kind = node:type(),
            name = ts.node_field_text(node, "name", bufnr, M.config.max_ts_field_len),
            start_row = sr,
            start_col = sc,
            end_row = er,
            end_col = ec,
        }

        if
            capture ~= "block.outer"
            or semantic_line_count(semantic) >= M.config.min_block_lines
        then
            areas[#areas + 1] = semantic
        end

        ::continue::
    end

    session.semantic_cache = {
        changetick = changetick,
        filetype = filetype,
        config_generation = semantic_config_generation,
        areas = areas,
    }
    return areas
end

---@param session Tracks.PointSession
---@param view Tracks.PointView
---@return Tracks.PointSemanticArea?
local function semantic_area_at(session, view)
    local areas = semantic_areas(session)
    if not areas then return nil end

    local row = view.lnum - 1
    local col = view.col
    local best = nil

    for _, semantic in ipairs(areas) do
        if not semantic_contains(semantic, row, col) then goto continue end

        local weight = M.config.capture_priority[semantic.capture]
        local lines = semantic_line_count(semantic)
        if not best or weight < best.weight or (weight == best.weight and lines < best.lines) then
            best = { area = semantic, weight = weight, lines = lines }
        end

        ::continue::
    end

    return best and best.area or nil
end

---@param area Tracks.PointSemanticArea
---@param other Tracks.PointSemanticArea
---@return boolean
local function same_semantic_owner(area, other)
    return area.capture == other.capture and area.kind == other.kind and area.name == other.name
end

---@param area Tracks.PointSemanticArea
---@param other Tracks.PointSemanticArea
---@return boolean
local function same_semantic_area(area, other)
    -- Entry semantics are reclassified from their extmark before matching, so
    -- both sides refer to the current parse. Exact ranges avoid conflating
    -- adjacent blocks or duplicate symbol names.
    return same_semantic_owner(area, other)
        and area.start_row == other.start_row
        and area.start_col == other.start_col
        and area.end_row == other.end_row
        and area.end_col == other.end_col
end

---@param entry Tracks.PointEntry
---@param semantic Tracks.PointSemanticArea
---@param view Tracks.PointView
---@return boolean
local function entry_matches(entry, semantic, view)
    if not same_semantic_area(entry.semantic, semantic) then return false end
    if semantic_line_count(semantic) <= M.config.max_semantic_area_lines then return true end
    return math.abs(entry.anchor_view.lnum - view.lnum) <= M.config.locality_lines
end

---@param session Tracks.PointSession
---@param view Tracks.PointView
---@param extmark_id number?
---@return number
local function set_extmark(session, view, extmark_id)
    local line_count = vim.api.nvim_buf_line_count(session.bufnr)
    local row = math.min(view.lnum - 1, line_count - 1)
    local line = vim.api.nvim_buf_get_lines(session.bufnr, row, row + 1, false)[1]
    local col = math.min(view.col, #line)
    return vim.api.nvim_buf_set_extmark(session.bufnr, M.config.namespace, row, col, {
        id = extmark_id,
        right_gravity = true,
        end_row = row,
        end_col = math.min(col + 1, #line),
        end_right_gravity = true,
    })
end

---@param session Tracks.PointSession
---@param entry Tracks.PointEntry
local function delete_entry_extmarks(session, entry)
    local extmarks = session.extmarks[entry]
    vim.api.nvim_buf_del_extmark(session.bufnr, M.config.namespace, extmarks.anchor)
    vim.api.nvim_buf_del_extmark(session.bufnr, M.config.namespace, extmarks.target)
    session.extmarks[entry] = nil
end

---@param session Tracks.PointSession
---@param extmark_id number
---@param view Tracks.PointView
local function refresh_view_from_extmark(session, extmark_id, view)
    local pos =
        vim.api.nvim_buf_get_extmark_by_id(session.bufnr, M.config.namespace, extmark_id, {})
    local old_lnum = view.lnum
    view.lnum = pos[1] + 1
    view.col = pos[2]

    -- Keep the saved viewport moving with the cursor anchor when edits happen
    -- above it. Extmarks track the cursor itself, not winsaveview()'s topline.
    local delta = view.lnum - old_lnum
    view.topline = math.max(1, view.topline + delta)
    view.botline = math.max(1, view.botline + delta)
end

---@param state Tracks.PointBufferState
---@param session Tracks.PointSession
local function sanitize_history(state, session)
    for index = #state.history.entries, 1, -1 do
        local entry = state.history.entries[index]
        local extmarks = session.extmarks[entry]
        refresh_view_from_extmark(session, extmarks.anchor, entry.anchor_view)
        refresh_view_from_extmark(session, extmarks.target, entry.target_view)

        local semantic = semantic_area_at(session, entry.anchor_view)
        if semantic and same_semantic_owner(entry.semantic, semantic) then
            entry.semantic = semantic
        else
            -- An extmark can move into an adjacent semantic node when its owner
            -- is deleted. Never transfer a landing to that unrelated owner.
            delete_entry_extmarks(session, entry)
            table.remove(state.history.entries, index)
            if index <= state.history.index then state.history.index = state.history.index - 1 end
        end
    end

    state.history.index = math.max(0, math.min(state.history.index, #state.history.entries))
end

---@param session Tracks.PointSession
---@param entry Tracks.PointEntry
---@param view Tracks.PointView
local function update_target(session, entry, view)
    entry.target_view = copy_view(view)
    local extmarks = session.extmarks[entry]
    extmarks.target = set_extmark(session, view, extmarks.target)
end

---@param session Tracks.PointSession
---@param view Tracks.PointView
---@param semantic Tracks.PointSemanticArea
---@return Tracks.PointEntry
local function new_entry(session, view, semantic)
    local entry = {
        anchor_view = copy_view(view),
        target_view = copy_view(view),
        semantic = semantic,
    }
    session.extmarks[entry] = {
        anchor = set_extmark(session, view),
        target = set_extmark(session, view),
    }
    return entry
end

---@param state Tracks.PointBufferState
---@param session Tracks.PointSession
---@param from number
local function truncate_history(state, session, from)
    for i = #state.history.entries, from, -1 do
        local removed = table.remove(state.history.entries, i)
        delete_entry_extmarks(session, removed)
    end
    state.history.index = math.min(state.history.index, #state.history.entries)
end

---@param history Tracks.PointHistory
---@param semantic Tracks.PointSemanticArea
---@param view Tracks.PointView
---@return number?
local function nearest_match(history, semantic, view)
    local best_index = nil
    local best_distance = math.huge

    for index, entry in ipairs(history.entries) do
        if entry_matches(entry, semantic, view) then
            local distance = math.abs(entry.anchor_view.lnum - view.lnum)
            if distance < best_distance then
                best_index = index
                best_distance = distance
            end
        end
    end

    return best_index
end

---@param state Tracks.PointBufferState
---@param session Tracks.PointSession
---@param view Tracks.PointView
---@return boolean recorded
local function record_point(state, session, view)
    local tick = vim.api.nvim_buf_get_changedtick(session.bufnr)
    if tick ~= session.changetick then
        sanitize_history(state, session)
        session.changetick = tick
    end

    local history = state.history
    local semantic = semantic_area_at(session, view)
    if not semantic then return false end

    local current = history.entries[history.index]

    -- Incidental movement inside the restored/current area updates its return
    -- target without branching or destroying forward history.
    if current and entry_matches(current, semantic, view) then
        update_target(session, current, view)
        return true
    end

    -- Landing in another area from the middle is an ordinary navigation branch.
    if history.index < #history.entries then
        truncate_history(state, session, history.index + 1)
    end

    local match = nearest_match(history, semantic, view)
    if match then
        -- Revisited areas are ordered by recency. A -> B -> C -> B therefore
        -- becomes A -> C -> B, making C the previous point.
        local entry = table.remove(history.entries, match)
        update_target(session, entry, view)
        table.insert(history.entries, entry)
        history.index = #history.entries
        return true
    end

    table.insert(history.entries, new_entry(session, view, semantic))
    history.index = #history.entries

    if #history.entries > M.config.max_history then
        local removed = table.remove(history.entries, 1)
        delete_entry_extmarks(session, removed)
        history.index = #history.entries
    end

    return true
end

---@param state Tracks.PointBufferState
---@param session Tracks.PointSession
---@return boolean recorded
local function commit_current(state, session)
    session.debounce:stop()
    return record_point(state, session, capture_view())
end

---@param session Tracks.PointSession
---@param entry Tracks.PointEntry
local function restore_entry(session, entry)
    local view = copy_view(entry.target_view)
    refresh_view_from_extmark(session, session.extmarks[entry].target, view)
    vim.fn.winrestview(view)

    entry.target_view = view
    session.ignore_cursor = { lnum = view.lnum, col = view.col }
end

---@param delta number
local function move(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local path = trackable_path(bufnr)
    local state = path and M.buffers[path] or nil
    local session = state and state.session or nil
    if not state or not session or session.bufnr ~= bufnr then return end

    -- Capture a pending landing before calculating the target. This makes an
    -- immediate <C-o> after a jump behave the same as waiting for the debounce.
    local recorded = commit_current(state, session)

    -- An unclassified location is deliberately absent from history. Moving
    -- backward from it should therefore return to the latest semantic landing,
    -- not skip that landing and restore the point before it.
    local target_index = state.history.index + delta
    if delta < 0 and not recorded then target_index = state.history.index end
    if target_index < 1 or target_index > #state.history.entries then return end

    restore_entry(session, state.history.entries[target_index])
    state.history.index = target_index
end

---@param state Tracks.PointBufferState
---@param session Tracks.PointSession
local function create_buffer_autocmds(state, session)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Tracks point history: capture landing after cursor settles",
        callback = function(ev)
            if not trackable_path(ev.buf) then return end

            local view = capture_view()
            if session.ignore_cursor then
                local ignored = session.ignore_cursor
                session.ignore_cursor = nil
                if view.lnum == ignored.lnum and view.col == ignored.col then return end
            end

            session.debounce:stop()
            local origin_win = vim.api.nvim_get_current_win()
            session.debounce:start(M.config.debounce_ms, 0, function()
                vim.schedule(function()
                    if
                        state.session ~= session
                        or not vim.api.nvim_win_is_valid(origin_win)
                        or vim.api.nvim_win_get_buf(origin_win) ~= session.bufnr
                        or not trackable_path(session.bufnr)
                    then
                        return
                    end

                    vim.api.nvim_win_call(
                        origin_win,
                        function() record_point(state, session, capture_view()) end
                    )
                end)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Tracks point history: commit pending landing before leaving",
        callback = function()
            if state.session == session and trackable_path(session.bufnr) then
                commit_current(state, session)
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = M.config.augroup_id,
        buffer = session.bufnr,
        desc = "Tracks point history: release volatile buffer state",
        callback = function()
            session.debounce:stop()
            session.debounce:close()
            if state.session == session then state.session = nil end
        end,
    })
end

---@param bufnr number
local function on_buf_enter(bufnr)
    local path = trackable_path(bufnr)
    if not path then return end

    local state = M.buffers[path]
    if state and state.session and state.session.bufnr == bufnr then return end

    if not state then
        state = { history = { index = 0, entries = {} } }
        M.buffers[path] = state
    end

    local session = {
        bufnr = bufnr,
        changetick = vim.api.nvim_buf_get_changedtick(bufnr),
        debounce = assert(vim.uv.new_timer()),
        extmarks = {},
        ignore_cursor = nil,
        semantic_cache = nil,
    }
    state.session = session

    for _, entry in ipairs(state.history.entries) do
        session.extmarks[entry] = {
            anchor = set_extmark(session, entry.anchor_view),
            target = set_extmark(session, entry.target_view),
        }
    end
    sanitize_history(state, session)
    create_buffer_autocmds(state, session)

    -- Seed after BufEnter handlers have finished (for example, after a plugin
    -- restores a saved cursor). BufLeave and prev/next commit synchronously, so
    -- an immediate transition is still captured if this callback has not run.
    if #state.history.entries == 0 then
        vim.schedule(function()
            if
                state.session == session
                and vim.api.nvim_get_current_buf() == bufnr
                and #state.history.entries == 0
                and trackable_path(bufnr)
            then
                record_point(state, session, capture_view())
            end
        end)
    end
end

function M.prev() move(-1) end
function M.next() move(1) end

function M.reset()
    for _, state in pairs(M.buffers) do
        local session = state.session
        if session then
            session.debounce:stop()
            session.debounce:close()
            vim.api.nvim_buf_clear_namespace(session.bufnr, M.config.namespace, 0, -1)
            state.session = nil
        end
    end
    M.buffers = {}

    if M.config.augroup_id then
        vim.api.nvim_clear_autocmds({ group = M.config.augroup_id })
        M.config.augroup_id = nil
    end
    M.setup()
end

---@param opts Tracks.PointJumpConfig?
function M.setup(opts)
    if opts then M.config = vim.tbl_deep_extend("force", M.config, opts) end
    semantic_config_generation = semantic_config_generation + 1

    if not M.config.augroup_id then
        M.config.augroup_id = vim.api.nvim_create_augroup("tracks_point_jump", { clear = true })
        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.config.augroup_id,
            desc = "Tracks point history: initialize buffer tracking",
            callback = function(ev) on_buf_enter(ev.buf) end,
        })
    end

    on_buf_enter(vim.api.nvim_get_current_buf())
end

if vim.g.tracks_test then M._test = { record_point = record_point } end

return M
