-- The timeline: a thin progress line along the bottom edge that grows into
-- a seek bar with a knob as the cursor gets closer.
--
-- Geometry and rendering are pure functions (tested outside mpv). Seeking
-- uses the global `mp` only when called, so tests can load this file.

local draw = require "draw"
local valid = require("state").valid_duration

local M = {}

-- Sizes in px at scale 1.
M.REST_HEIGHT = 2   -- line at rest
M.FULL_HEIGHT = 5   -- line fully grown
M.LIFT = 6          -- distance from the bottom edge when fully grown
M.KNOB_SIZE = 13    -- knob diameter
M.ZONE_HEIGHT = 24  -- clickable area, taller than the line itself
M.HALO = 1          -- dark halo around the line and the knob

local BLACK = "&H000000&"
local DRAG_SEEK_INTERVAL = 1 / 30 -- at most this many seeks per second
local FAST_DRAG = 30              -- video seconds per second of dragging
local END_MARGIN = 0.5            -- seconds; seeks stop short of the end

local function clamp(v, lo, hi)
    if v ~= v then return lo end
    return math.max(lo, math.min(hi, v))
end

local function lerp(a, b, t) return a + (b - a) * t end
local function round(n) return math.floor(n + 0.5) end

function M.time_to_x(t, duration, w)
    if not t or not valid(duration) or w <= 0 then return 0 end
    return w * clamp(t / duration, 0, 1)
end

function M.x_to_time(x, duration, w)
    if not valid(duration) or w <= 0 then return 0 end
    return duration * clamp(x / w, 0, 1)
end

-- End of the progress line in whole pixels: the line only needs a repaint
-- when this changes.
function M.progress_px(t, duration, w)
    return math.floor(M.time_to_x(t, duration, w))
end

-- Top of the clickable zone.
function M.zone_top(h, scale)
    return h - round(M.ZONE_HEIGHT * scale)
end

function M.in_zone(x, y, w, h, scale)
    return x >= 0 and x < w and y >= M.zone_top(h, scale) and y < h
end

-- Where the line sits for visibility v (0..1). Heights are whole pixels so
-- the line stays sharp.
function M.layout(w, h, scale, v)
    v = clamp(v, 0, 1)
    local thickness = math.max(1, round(lerp(M.REST_HEIGHT, M.FULL_HEIGHT, v) * scale))
    local y1 = h - round(M.LIFT * scale * v)
    return {
        x0 = 0, x1 = w,
        y0 = y1 - thickness, y1 = y1,
        knob_r = M.KNOB_SIZE * scale / 2,
        halo = M.HALO * scale,
    }
end

-- ASS text for the bar. st: { w, h, scale, time, duration }.
-- drag_time, when set, replaces the playback time (the knob follows the
-- cursor while dragging, before the seek lands).
function M.render(st, v, opts, drag_time)
    if not valid(st.duration) or st.w <= 0 or st.h <= 0 then return "" end
    v = clamp(v, 0, 1)
    local fade = opts.idle_line and 1 or v
    if fade <= 0 then return "" end

    local g = M.layout(st.w, st.h, st.scale, v)
    local px = M.time_to_x(drag_time or st.time, st.duration, st.w)
    local accent = draw.color(opts.accent) or "&HFFFFFF&"
    local white = "&HFFFFFF&"
    local out = {
        draw.rect(g.x0, g.y0 - g.halo, g.x1, g.y1 + g.halo,
            { color = BLACK, opacity = 0.45 * fade, blur = g.halo }),
        draw.rect(g.x0, g.y0, g.x1, g.y1,
            { color = white, opacity = lerp(opts.idle_line and 0.15 or 0, 0.35, v) }),
        draw.rect(g.x0, g.y0, px, g.y1,
            { color = accent, opacity = fade * lerp(0.75, 1, v) }),
    }
    if v > 0.01 then
        -- Keep the knob inside the window at both ends.
        local r = g.knob_r * lerp(0.5, 1, v)
        local cx = clamp(px, r, st.w - r)
        local cy = (g.y0 + g.y1) / 2
        out[#out + 1] = draw.circle(cx, cy, r + g.halo,
            { color = BLACK, opacity = 0.45 * v, blur = g.halo })
        out[#out + 1] = draw.circle(cx, cy, r, { color = accent, opacity = v })
    end
    return table.concat(out, "\n")
end

-- Seeking -----------------------------------------------------------------

-- Seek target for cursor x. It stops END_MARGIN before the end: seeking to
-- the exact duration ends the file, which is never what a drag past the
-- right edge means.
function M.seek_target(x, duration, w)
    local t = M.x_to_time(x, duration, w)
    return math.min(t, math.max(0, duration - END_MARGIN))
end

local drag -- nil, or { target, px, resume, last_time, last_target, exact_target, timer }

local function seek(t, mode)
    mp.commandv("seek", ("%.3f"):format(t), "absolute+" .. mode)
    if drag then drag.exact_target = mode == "exact" and t or nil end
end

-- Slow drags seek exactly, fast drags by keyframes.
local function drag_seek()
    if not drag then return end
    local now = mp.get_time()
    local speed = math.abs(drag.target - drag.last_target) /
        math.max(now - drag.last_time, 1e-3)
    seek(drag.target, speed > FAST_DRAG and "keyframes" or "exact")
    drag.last_time, drag.last_target = now, drag.target
end

function M.dragging() return drag ~= nil end
function M.drag_time() return drag and drag.target end

-- Mouse button down on the bar: exact seek to the cursor, start dragging.
-- A drag still running means its button up was lost: drop it first.
function M.press(x, st, opts)
    if not valid(st.duration) then return end
    if drag then M.release(false) end
    local t = M.seek_target(x, st.duration, st.w)
    drag = { target = t, px = math.floor(x), resume = false,
             last_time = mp.get_time(), last_target = t }
    drag.timer = mp.add_timeout(DRAG_SEEK_INTERVAL, drag_seek, true)
    if opts.pause_on_drag and not st.paused then
        mp.set_property_bool("pause", true)
        drag.resume = true
    end
    seek(t, "exact")
end

-- Cursor moved while dragging: seek at most DRAG_SEEK_INTERVAL apart, only
-- when the target moved by at least one pixel.
function M.move(x, st)
    if not drag then return end
    local px = math.floor(clamp(x, 0, st.w))
    if px == drag.px then return end
    drag.px = px
    drag.target = M.seek_target(px, st.duration, st.w)
    if drag.timer:is_enabled() then return end
    local wait = drag.last_time + DRAG_SEEK_INTERVAL - mp.get_time()
    if wait <= 0 then
        drag_seek()
    else
        drag.timer.timeout = wait
        drag.timer:kill()
        drag.timer:resume()
    end
end

-- End of the drag: one last exact seek, unless the last seek was already
-- an exact one to the same place. final_seek = false drops the drag without
-- seeking (for example when the file changed underneath).
function M.release(final_seek)
    if not drag then return end
    local d = drag
    drag = nil
    d.timer:kill()
    if final_seek ~= false and d.exact_target ~= d.target then
        seek(d.target, "exact")
    end
    -- Resume only if the pause suji set is still there: the user may have
    -- unpaused by hand during the drag.
    if d.resume and mp.get_property_bool("pause") then
        mp.set_property_bool("pause", false)
    end
end

return M
