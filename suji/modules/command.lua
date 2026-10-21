-- command:icon:command?text in the controls option: a button that runs an
-- mpv command. One instance per element. The icon comes from core/icons.lua
-- by name; for a name it does not know, the initial is drawn instead. The
-- text is kept but not drawn: suji has no floating tooltips, by design.
-- The buttons other scripts define (modules/button.lua) are made here too,
-- with three more fields: active, badge and hide.

local unpack = table.unpack or unpack

local M = {}

-- The last button pressed and when: a menu another script opens right
-- after comes out of it (core/messages.lua). Weak, so the button of an
-- old controls option can still go.
local last = setmetatable({}, { __mode = "v" })

-- The last button pressed and the time of the press, forgotten once read.
function M.last_press()
    local b, t = last.button, last.time
    last.button, last.time = nil, nil
    return b, t
end

-- A short line in the accent under the icon, with the dark halo of the bar.
local function mark(ctx, cx, cy, v)
    local d, s = ctx.draw, ctx.state.scale
    local x0, x1, y0, y1 = cx - 6 * s, cx + 6 * s, cy + 14 * s, cy + 16 * s
    return d.rect(x0 - s, y0 - s, x1 + s, y1 + s, { color = "&H000000&", opacity = 0.45 * v, blur = s }) .. "\n" ..
        d.rect(x0, y0, x1, y1, { color = d.color(ctx.opts.accent) or "&HFFFFFF&", opacity = v })
end

-- e: the element from core/controls.lua ({ icon, command, text }). The
-- command is a string for mp.command or a list for mp.commandv.
function M.new(e)
    local b = { icon = e.icon, command = e.command, text = e.text }

    function b.available() return not b.hide end

    function b.width(ctx) return ctx.BUTTON * ctx.state.scale end

    function b.render(ctx, box, v)
        local cx, s = (box.x0 + box.x1) / 2, ctx.state.scale
        local out = ctx.icon(b.icon, cx, box.cy, v) or
            ctx.draw.text(cx, box.cy, 5, ctx.text.upper(ctx.text.prefix(b.icon, 1)), ctx.style(15, v))
        if b.active then out = out .. "\n" .. mark(ctx, cx, box.cy, v) end
        if b.badge then
            out = out .. "\n" .. ctx.draw.text(cx + 11 * s, box.cy - 10 * s, 5, b.badge, ctx.style(10, v, true))
        end
        return out
    end

    function b.press()
        last.button, last.time = b, mp.get_time()
        if type(b.command) == "table" then
            mp.commandv(unpack(b.command))
        elseif b.command then
            mp.command(b.command)
        end
    end

    return b
end

return M
