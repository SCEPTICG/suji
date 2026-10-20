-- command:icon:command?text in the controls option: a button that runs an
-- mpv command. One instance per element. The icon comes from core/icons.lua
-- by name; for a name it does not know, the initial is drawn instead. The
-- text is kept but not drawn: suji has no floating tooltips, by design.

local M = {}

-- e: the element from core/controls.lua ({ icon, command, text }).
function M.new(e)
    local b = { icon = e.icon, command = e.command, text = e.text }

    function b.width(ctx) return ctx.BUTTON * ctx.state.scale end

    function b.render(ctx, box, v)
        local cx = (box.x0 + box.x1) / 2
        return ctx.icon(b.icon, cx, box.cy, v) or
            ctx.draw.text(cx, box.cy, 5, ctx.text.upper(ctx.text.prefix(b.icon, 1)), ctx.style(15, v))
    end

    function b.press() mp.command(b.command) end

    return b
end

return M
