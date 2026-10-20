-- Volume: the speaker icon (a click mutes) and a slider to its right (click
-- or drag). The wheel over either changes the volume by 5.

local M = {}

local SLIDER_W, SLIDER_H = 64, 3 -- px at scale 1

local volume, mute = 100, false

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Cursor x on a slider from x0 to x1 -> volume 0..100. The last pixel
-- that can be clicked (x1 - 1) gives 100.
function M.x_to_volume(x, x0, x1)
    return math.floor(clamp((x - x0) / (x1 - 1 - x0), 0, 1) * 100 + 0.5)
end

local function slider_x0(ctx, box) return box.x0 + ctx.BUTTON * ctx.state.scale end

local function set_volume(ctx, box, x)
    local v = M.x_to_volume(x, slider_x0(ctx, box), box.x1)
    if v ~= volume then mp.commandv("set", "volume", tostring(v)) end
end

function M.init(ctx)
    ctx.watch("volume", "number", function(v) volume = v; return true end)
    ctx.watch("mute", "bool", function(m) mute = m; return true end)
end

function M.width(ctx) return (ctx.BUTTON + SLIDER_W) * ctx.state.scale end

function M.render(ctx, box, v)
    local s, draw = ctx.state.scale, ctx.draw
    local x0, x1 = slider_x0(ctx, box), box.x1
    local y0, y1 = box.cy - SLIDER_H * s / 2, box.cy + SLIDER_H * s / 2
    local fill = x0 + (x1 - x0) * clamp((tonumber(volume) or 0) / 100, 0, 1)
    return table.concat({
        ctx.icon(ctx.icons.volume_name(volume, mute), (box.x0 + x0) / 2, box.cy, v),
        draw.rect(x0 - s, y0 - s, x1 + s, y1 + s, { color = "&H000000&", opacity = 0.45 * v, blur = s }),
        draw.rect(x0, y0, x1, y1, { opacity = 0.3 * v }),
        draw.rect(x0, y0, fill, y1, { opacity = v }),
    }, "\n")
end

-- The icon mutes; the slider sets the volume and holds the mouse.
function M.press(ctx, box, x)
    if x < slider_x0(ctx, box) then
        mp.commandv("cycle", "mute")
        return
    end
    set_volume(ctx, box, x)
    return true
end

function M.move(ctx, box, x) set_volume(ctx, box, x) end

function M.wheel(_, dir) mp.commandv("add", "volume", tostring(5 * dir)) end

return M
