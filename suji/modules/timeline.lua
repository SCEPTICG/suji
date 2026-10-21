-- The timeline: a thin line along the bottom edge that grows into a seek
-- bar with a knob. Geometry and drawing are pure; seeking uses the global
-- `mp` only when called, so tests can load this file.
--
-- A module of suji that is always there: it is not part of the controls
-- option, its zone is the bottom edge (layout.bar_zone) and it holds the
-- mouse while dragging. See core/modules.lua for the contract.

local draw = require "core.draw"
local valid = require("core.state").valid_duration

local M = {}

-- Sizes in px at scale 1.
M.REST_HEIGHT = 2   -- line at rest
M.FULL_HEIGHT = 5   -- line fully grown
M.LIFT = 6          -- distance from the bottom edge when fully grown
M.KNOB_SIZE = 13    -- knob diameter
M.ZONE_HEIGHT = 24  -- clickable area, taller than the line itself
M.HALO = 1          -- dark halo around the line and the knob
M.MARK_WIDTH = 2    -- chapter marks, at least twice as far apart
M.MAX_MARKS = 500   -- chapter marks drawn at most

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

-- End of the cached range that contains time t, from the seekable-ranges
-- of demuxer-cache-state. nil when t is not inside any of them.
function M.cached_until(ranges, t)
    if type(ranges) ~= "table" or type(t) ~= "number" then return nil end
    local best
    for _, r in ipairs(ranges) do
        local a, b = type(r) == "table" and tonumber(r.start), type(r) == "table" and tonumber(r["end"])
        if a and b and a <= t and t <= b and (not best or b > best) then best = b end
    end
    return best
end

-- x of every chapter start inside the file, except one at the very start,
-- at most one every `spacing` px (1 when not given). The spacing grows
-- with the width so there are never more than MAX_MARKS, spread along the
-- whole bar: a huge chapter list stays cheap and its ASS small. The last
-- result is kept: the list is only walked again when something changed.
local last_marks = {}
function M.chapter_xs(chapters, duration, w, spacing)
    if not (w > 0 and w < math.huge) then return {} end -- NaN too
    spacing = math.max(spacing == spacing and spacing or 1, w / M.MAX_MARKS)
    local m = last_marks
    if m.chapters == chapters and m.duration == duration and m.w == w and m.spacing == spacing then return m.xs end
    local xs, seen = {}, {}
    if type(chapters) == "table" and valid(duration) then
        for _, c in ipairs(chapters) do
            local t = type(c) == "table" and tonumber(c.time)
            local x = t and t > 0 and t < duration and M.time_to_x(t, duration, w)
            if x ~= x then x = nil end -- NaN
            local slot = x and math.min(math.floor(x / spacing), M.MAX_MARKS - 1)
            if slot and not seen[slot] then
                seen[slot] = true
                xs[#xs + 1] = x
            end
        end
    end
    last_marks = { chapters = chapters, duration = duration, w = w, spacing = spacing, xs = xs }
    return xs
end

-- ASS text for the bar. st: suji's state. drag_time, when set, replaces the
-- playback time (the knob follows the cursor before the seek lands).
-- cache_ranges and chapters: as in demuxer-cache-state and chapter-list.
function M.ass(st, v, opts, drag_time, cache_ranges, chapters)
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
    }
    -- Cached range and chapter marks only while the bar is grown.
    local cached = v > 0 and M.cached_until(cache_ranges, st.time)
    if cached and cached > st.time then
        out[#out + 1] = draw.rect(M.time_to_x(st.time, st.duration, st.w), g.y0,
            M.time_to_x(cached, st.duration, st.w), g.y1, { color = white, opacity = 0.18 * v })
    end
    out[#out + 1] = draw.rect(g.x0, g.y0, px, g.y1, { color = accent, opacity = fade * lerp(0.75, 1, v) })
    local marks, hw = {}, M.MARK_WIDTH * st.scale / 2
    for _, x in ipairs(v > 0 and M.chapter_xs(chapters, st.duration, st.w, 2 * M.MARK_WIDTH * st.scale) or {}) do
        marks[#marks + 1] = { x - hw, g.y0, x + hw, g.y0, x + hw, g.y1, x - hw, g.y1 }
    end
    if #marks > 0 then out[#out + 1] = draw.poly(marks, { color = BLACK, opacity = 0.55 * v }) end
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

-- End of the drag: one last exact seek, unless the last seek was already
-- an exact one to the same place. commit = false drops the drag without
-- seeking (for example when the file changed underneath).
function M.release(_, commit)
    if not drag then return end
    local d = drag
    drag = nil
    d.timer:kill()
    if commit ~= false and d.exact_target ~= d.target then
        seek(d.target, "exact")
    end
    -- Resume only if the pause suji set is still there: the user may have
    -- unpaused by hand during the drag.
    if d.resume and mp.get_property_bool("pause") then
        mp.set_property_bool("pause", false)
    end
end

-- Mouse button down on the bar: exact seek to the cursor, start dragging.
-- A drag still running means its button up was lost: drop it first.
function M.press(ctx, _, x)
    local st = ctx.state
    if not valid(st.duration) then return end
    if drag then M.release(ctx, false) end
    local t = M.seek_target(x, st.duration, st.w)
    drag = { target = t, px = math.floor(x), resume = false,
             last_time = mp.get_time(), last_target = t }
    drag.timer = mp.add_timeout(DRAG_SEEK_INTERVAL, drag_seek, true)
    if ctx.opts.pause_on_drag and not st.paused then
        mp.set_property_bool("pause", true)
        drag.resume = true
    end
    seek(t, "exact")
    return true
end

-- Cursor moved while dragging: seek at most DRAG_SEEK_INTERVAL apart, only
-- when the target moved by at least one pixel.
function M.move(ctx, _, x)
    local st = ctx.state
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

-- The module -----------------------------------------------------------------

local cache_ranges, chapters -- seekable-ranges of demuxer-cache-state, chapter-list
-- Last values drawn, to repaint only when what is shown changes:
local progress_px = -1 -- progress line end in whole pixels
local cache_px = -1    -- end of the cached range in whole pixels

-- Repaint when the shown line's end moves a whole pixel, or when the end
-- of the cached range moves with the controls up.
local function update(ctx)
    local st = ctx.state
    local px = M.progress_px(st.time, st.duration, st.w)
    if px ~= progress_px then
        progress_px = px
        if (ctx.opts.enabled and ctx.opts.idle_line) or ctx.visible() then ctx.request() end
    end
    if not ctx.visible() then return end
    local cached = M.cached_until(cache_ranges, st.time)
    local c = cached and M.progress_px(cached, st.duration, st.w) or -1
    if c ~= cache_px then
        cache_px = c
        ctx.request()
    end
end

function M.init(ctx)
    local function on_change() update(ctx) end
    ctx.watch("osd-dimensions", "native", on_change)
    ctx.watch("time-pos", "number", on_change)
    ctx.watch("duration", "number", on_change)
    ctx.watch("demuxer-cache-state", "native", function(c)
        cache_ranges = type(c) == "table" and c["seekable-ranges"] or nil
        update(ctx)
    end)
    ctx.watch("chapter-list", "native", function(c)
        chapters = c
        return true
    end)
end

function M.render(ctx, _, v)
    return M.ass(ctx.state, v, ctx.opts, M.drag_time(), cache_ranges, chapters)
end

return M
