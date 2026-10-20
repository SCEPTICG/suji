-- Fullscreen button: shows what a click does (to fullscreen, or back).

local M = {}

local fullscreen = false

function M.init(ctx)
    ctx.watch("fullscreen", "bool", function(on)
        fullscreen = on
        return true
    end)
end

function M.width(ctx) return ctx.BUTTON * ctx.state.scale end

function M.render(ctx, box, v)
    return ctx.icon(fullscreen and "windowed" or "fullscreen", (box.x0 + box.x1) / 2, box.cy, v)
end

function M.press() mp.commandv("cycle", "fullscreen") end

return M
