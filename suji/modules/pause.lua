-- Play/pause button.

local M = {}

function M.width(ctx) return ctx.BUTTON * ctx.state.scale end

function M.render(ctx, box, v)
    return ctx.icon(ctx.state.paused and "play" or "pause", (box.x0 + box.x1) / 2, box.cy, v)
end

function M.press() mp.commandv("cycle", "pause") end

return M
