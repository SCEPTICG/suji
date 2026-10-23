-- Volume: the speaker icon (a click mutes) and a slider to its right (click
-- or drag). The slider unfolds while the cursor is on the speaker, pushing
-- what follows to the right, and folds again a moment after the cursor has
-- left the speaker and the slider; never while dragging it. The wheel over
-- either changes the volume by 5.

local animation = require "core.animation"

local M = {}

local SLIDER_W, SLIDER_H = 64, 3 -- px at scale 1
local PAD = 6                    -- px at scale 1, after the slider unfolded
local UNFOLD = 0.15              -- seconds to unfold or fold
local FOLD_DELAY = 0.4           -- seconds after the cursor left, so it does not flicker

local volume, mute = 100, false
local tween = animation.new(UNFOLD) -- 0 folded, 1 unfolded
local over, dragging = false, false -- the cursor is on its zone; the slider holds the mouse
local settled = true                -- the row was laid out again after the last fold or unfold
local fold_timer                    -- one shot, armed when the cursor leaves

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Cursor x on a slider from x0 to x1 -> volume 0..100. The last pixel
-- that can be clicked (x1 - 1) gives 100.
function M.x_to_volume(x, x0, x1)
    return math.floor(clamp((x - x0) / (x1 - 1 - x0), 0, 1) * 100 + 0.5)
end

-- How far unfolded, 0..1.
function M.unfolded() return animation.value(tween, mp.get_time()) end

local function unfold(ctx, target)
    if target == tween.to then return end
    animation.set_target(tween, target, mp.get_time())
    settled = false
    ctx.request()
end

-- The slider in box: from after the speaker to before the pad, both
-- taken from the box, so a press and the paint agree.
local function slider_x0(ctx, box) return box.x0 + ctx.BUTTON * ctx.state.scale end
local function slider_x1(ctx, box)
    local x0 = slider_x0(ctx, box)
    return x0 + (box.x1 - x0) * SLIDER_W / (SLIDER_W + PAD)
end

local function set_volume(ctx, box, x)
    local x0, x1 = slider_x0(ctx, box), slider_x1(ctx, box)
    if x1 - 1 <= x0 then return end -- barely unfolded
    local v = M.x_to_volume(x, x0, x1)
    if v ~= volume then mp.commandv("set", "volume", tostring(v)) end
end

function M.init(ctx)
    ctx.watch("volume", "number", function(v) volume = v; return true end)
    ctx.watch("mute", "bool", function(m) mute = m; return true end)
    fold_timer = mp.add_timeout(FOLD_DELAY, function()
        if not over and not dragging then unfold(ctx, 0) end
    end, true)
end

function M.width(ctx) return (ctx.BUTTON + (SLIDER_W + PAD) * M.unfolded()) * ctx.state.scale end

function M.render(ctx, box, v)
    -- Painted while it unfolds or folds; then the row is laid out once
    -- more, so the zones under a still cursor follow. With the controls
    -- hidden (v = 0) render is not called, so settled can stay false until
    -- they come back: harmless, layout.current() reads the width of now
    -- and that first paint lays out the row again.
    local now = mp.get_time()
    if animation.running(tween, now) then
        ctx.request()
    elseif not settled then
        settled = true
        ctx.relayout()
    end
    local s, draw = ctx.state.scale, ctx.draw
    local x0, x1 = slider_x0(ctx, box), slider_x1(ctx, box)
    local icon = ctx.icon(ctx.icons.volume_name(volume, mute), x0 - ctx.BUTTON * s / 2, box.cy, v)
    if x1 - x0 < 1 then return icon end
    local e = clamp((x1 - x0) / (SLIDER_W * s), 0, 1) * v
    local y0, y1 = box.cy - SLIDER_H * s / 2, box.cy + SLIDER_H * s / 2
    local fill = x0 + (x1 - x0) * clamp((tonumber(volume) or 0) / 100, 0, 1)
    return table.concat({
        icon,
        draw.rect(x0 - s, y0 - s, x1 + s, y1 + s, { color = "&H000000&", opacity = 0.45 * e, blur = s }),
        draw.rect(x0, y0, x1, y1, { opacity = 0.3 * e }),
        draw.rect(x0, y0, fill, y1, { opacity = e }),
    }, "\n")
end

function M.hover(ctx, on)
    over = on
    if on then
        fold_timer:kill()
        unfold(ctx, 1)
    elseif not dragging then
        fold_timer:kill()
        fold_timer:resume()
    end
end

-- The icon mutes; the slider sets the volume and holds the mouse.
function M.press(ctx, box, x)
    if x < slider_x0(ctx, box) then
        mp.commandv("cycle", "mute")
        return
    end
    set_volume(ctx, box, x)
    dragging = true
    return true
end

function M.move(ctx, box, x) set_volume(ctx, box, x) end

-- A drag that ended away from the volume folds it after the delay.
function M.release(ctx)
    dragging = false
    if not over then M.hover(ctx, false) end
end

function M.wheel(_, dir) mp.commandv("add", "volume", tostring(5 * dir)) end

return M
