-- The row of controls above the timeline (play/pause, time, volume,
-- fullscreen), the title above it and the time under the cursor.
--
-- Pure functions, tested outside mpv. Text widths come from the caller's
-- measure(ass, guess) function, so libass does the measuring in mpv and the
-- tests can use a fake.

local draw = require "draw"
local icons = require "icons"
local bar = require "elements.bar"
local valid = require("state").valid_duration

local M = {}

-- Sizes in px at scale 1.
local ROW_LIFT = 40    -- centre of the row above the bottom edge
local SIDE = 20        -- row margin on both sides
local BUTTON = 44      -- clickable square of a button
local ICON = 22
local GAP = 8
local VOLUME_W, VOLUME_H = 64, 3
local TITLE_X, TITLE_LIFT = 32, 68
local ELLIPSIS = "\226\128\166"

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Seconds -> "mm:ss", or "h:mm:ss" when long. Unknown -> dashes.
function M.format_time(t, long)
    if type(t) ~= "number" or t ~= t or math.abs(t) == math.huge then
        return long and "-:--:--" or "--:--"
    end
    local n = math.floor(math.abs(t))
    local sign = (t < 0 and n > 0) and "-" or ""
    if long then
        return ("%s%d:%02d:%02d"):format(sign, math.floor(n / 3600), math.floor(n / 60) % 60, n % 60)
    end
    return ("%s%02d:%02d"):format(sign, math.floor(n / 60), n % 60)
end

-- "09:48 / 23:40", or "09:48 / -13:52" with remaining. Both halves use the
-- long form when the file lasts an hour or more.
function M.time_text(time, duration, remaining)
    local known = type(time) == "number" and time == time
    local long = math.max(known and time or 0, valid(duration) and duration or 0) >= 3600
    local right
    if valid(duration) and remaining then
        right = "-" .. M.format_time(math.max(0, math.floor(duration) - math.floor(known and time or 0)), long)
    else
        right = M.format_time(valid(duration) and duration or nil, long)
    end
    return M.format_time(time, long) .. " / " .. right
end

-- UTF-8 aware length and prefix, so a cut never splits a character.
function M.len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end

function M.prefix(s, n)
    local count = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 128 or b >= 192 then
            count = count + 1
            if count > n then return s:sub(1, i - 1) end
        end
    end
    return s
end

-- text, or its longest prefix plus "…" that is at most max_w wide.
function M.fit(text, max_w, width_of)
    if max_w <= 0 then return "" end
    if width_of(text) <= max_w then return text end
    local lo, hi = 0, M.len(text) - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if width_of(M.prefix(text, mid) .. ELLIPSIS) <= max_w then lo = mid else hi = mid - 1 end
    end
    return (M.prefix(text, lo):gsub("%s+$", "")) .. ELLIPSIS
end

-- Where everything goes. Zones are { x0, y0, x1, y1 } in window px.
function M.layout(w, h, s)
    local cy, half = h - ROW_LIFT * s, BUTTON * s / 2
    local function zone(x0, x1) return { x0 = x0, y0 = cy - half, x1 = x1 or x0 + 2 * half, y1 = cy + half } end
    local fullscreen = zone(w - SIDE * s - 2 * half)
    local vx1 = fullscreen.x0 - GAP * s
    local volume = zone(vx1 - VOLUME_W * s, vx1)
    local mute = zone(volume.x0 - 2 * half)
    return {
        cy = cy, pause = zone(SIDE * s), time_x = (SIDE + GAP) * s + 2 * half,
        mute = mute, volume = volume, fullscreen = fullscreen,
        title_x = TITLE_X * s, title_y = h - TITLE_LIFT * s,
        title_w = mute.x0 - (TITLE_X + 24) * s,
    }
end

local function inside(z, x, y) return x >= z.x0 and x < z.x1 and y >= z.y0 and y < z.y1 end

-- Name of the control under (x, y): "pause", "time", "mute", "volume",
-- "fullscreen", or nil. time_w is the measured width of the time.
function M.hit(lay, x, y, time_w)
    for _, name in ipairs({ "pause", "mute", "volume", "fullscreen" }) do
        if inside(lay[name], x, y) then return name end
    end
    local p = lay.pause
    if inside({ x0 = lay.time_x, y0 = p.y0, x1 = lay.time_x + time_w, y1 = p.y1 }, x, y) then
        return "time"
    end
end

-- Cursor x on the volume slider -> volume 0..100.
function M.x_to_volume(x, lay)
    local z = lay.volume
    return math.floor(clamp((x - z.x0) / (z.x1 - z.x0), 0, 1) * 100 + 0.5)
end

local function style(st, size, opacity, bold, spacing)
    return { font = st.font, size = size * st.scale, opacity = opacity, scale = st.scale,
             bold = bold, spacing = spacing and spacing * st.scale }
end

-- ASS text for visibility v (> 0) and the time width (for M.hit).
-- st: suji's state. tip_x, tip_time: cursor x and the time under it, when
-- the cursor is on the timeline.
function M.render(st, v, measure, tip_x, tip_time)
    local s = st.scale
    local lay = M.layout(st.w, st.h, s)
    local function width(text, size, bold, spacing)
        local ass = draw.text(0, 0, 7, text, style(st, size, 1, bold, spacing))
        return measure(ass, M.len(text) * size * s * 0.55)
    end
    local function icon(name, z)
        return draw.poly(icons.shape(name, (z.x0 + z.x1) / 2, lay.cy, ICON * s),
            { opacity = v, outline = draw.outline(s, v) })
    end

    local time = M.time_text(st.time, st.duration, st.remaining)
    local time_w = width((time:gsub("%d", "0")), 15)
    local vz = lay.volume
    local vy0, vy1 = lay.cy - VOLUME_H * s / 2, lay.cy + VOLUME_H * s / 2
    local fill = vz.x0 + (vz.x1 - vz.x0) * clamp((tonumber(st.volume) or 0) / 100, 0, 1)
    local out = {
        icon(st.paused and "play" or "pause", lay.pause),
        draw.text(lay.time_x, lay.cy, 4, time, style(st, 15, v)),
        icon(icons.volume_name(st.volume, st.mute), lay.mute),
        draw.rect(vz.x0 - s, vy0 - s, vz.x1 + s, vy1 + s, { color = "&H000000&", opacity = 0.45 * v, blur = s }),
        draw.rect(vz.x0, vy0, vz.x1, vy1, { opacity = 0.3 * v }),
        draw.rect(vz.x0, vy0, fill, vy1, { opacity = v }),
        icon(st.fullscreen and "windowed" or "fullscreen", lay.fullscreen),
    }

    -- Title: one line, or series above episode when both are known.
    local top, main
    if st.series and st.episode then top, main = st.series:upper(), st.episode
    else main = st.episode or st.series or st.title or "" end
    main = M.fit(main, lay.title_w, function(t) return width(t, 20, true) end)
    out[#out + 1] = draw.text(lay.title_x, lay.title_y, 1, main, style(st, 20, v, true))
    if top then
        top = M.fit(top, lay.title_w, function(t) return width(t, 13, false, 1.5) end)
        out[#out + 1] = draw.text(lay.title_x, lay.title_y - 22 * s, 1, top, style(st, 13, 0.8 * v, false, 1.5))
    end

    -- Time under the cursor, centred on it but kept inside the window.
    if tip_x and tip_time then
        local text = M.format_time(tip_time, valid(st.duration) and st.duration >= 3600)
        local half = width((text:gsub("%d", "0")), 13) / 2
        local y = bar.layout(st.w, st.h, s, v).y0 - 10 * s
        out[#out + 1] = draw.text(clamp(tip_x, half, st.w - half), y, 2, text, style(st, 13, v))
    end
    return table.concat(out, "\n"), time_w
end

return M
