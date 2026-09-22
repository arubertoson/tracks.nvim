local app = require("app")

local M = {}

local routes = {
    create = function(request) return app.create_track(request.name, request.path) end,

    play = function(request) return app.play(request.track) end,
}

function M.dispatch(request)
    local handler = routes[request.action]
    if not handler then return nil, "unknown action: " .. request.action end

    return handler(request)
end

return M
