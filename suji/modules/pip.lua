-- Picture in picture button (core/pip.lua): in the row it enters, and in
-- picture in picture it is the way back, at the top right of the window
-- (core/layout.lua).

local pip = require "core.pip"

local M = { once = true } -- a double click enters, or leaves, once

function M.width(ctx) return ctx.BUTTON * ctx.state.scale end

function M.render(ctx, box, v)
    return ctx.icon(ctx.state.pip and "pip_exit" or "pip", (box.x0 + box.x1) / 2, box.cy, v)
end

function M.press() pip.toggle() end

return M
