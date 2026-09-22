---@module "tracks.treesitter"
---Treesitter operations needed by semantic point history.

local M = {}

---@class Tracks.TreesitterIterator
---@field iter fun(...): integer?, TSNode?
---@field query vim.treesitter.Query

---@param bufnr integer
---@return Tracks.TreesitterIterator|nil
function M.iter_textobj_captures(bufnr)
    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then return nil end

    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok_parser or not parser then return nil end

    local ok_parse, trees = pcall(parser.parse, parser)
    local tree = ok_parse and trees and trees[1] or nil
    local root = tree and tree:root() or nil
    if not root then return nil end

    local ok_query, query = pcall(vim.treesitter.query.get, lang, "textobjects")
    if not ok_query or not query then return nil end

    local start_row, _, end_row = root:range()
    return {
        iter = query:iter_captures(root, bufnr, start_row, end_row + 1),
        query = query,
    }
end

---@param node TSNode
---@param field string
---@param bufnr integer
---@param max_len integer
---@return string|nil
function M.node_field_text(node, field, bufnr, max_len)
    local field_node = node:field(field)[1]
    if field_node then
        local text = vim.treesitter.get_node_text(field_node, bufnr)
        if text and text ~= "" then return text end
    end

    local row, col = node:range()
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local snippet =
        vim.api.nvim_buf_get_text(bufnr, row, col, row, math.min(#line, col + max_len), {})[1]
    return snippet and snippet ~= "" and snippet or nil
end

return M
