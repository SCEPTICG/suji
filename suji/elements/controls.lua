-- The row of controls above the timeline (play/pause, time, volume,
-- fullscreen) and the title above it. Pure functions: text widths come from
-- the caller's measure(ass, guess), libass in mpv and a fake in the tests.

local draw = require "draw"
local icons = require "icons"
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

-- The time in two parts: "09:48" and " / 23:40" (" / -13:52" with
-- remaining), long form from an hour on. shown replaces the first part.
function M.time_text(time, duration, remaining, shown)
    local known = type(time) == "number" and time == time
    local long = math.max(known and time or 0, valid(duration) and duration or 0) >= 3600
    local right
    if valid(duration) and remaining then
        right = "-" .. M.format_time(math.max(0, math.floor(duration) - math.floor(known and time or 0)), long)
    else
        right = M.format_time(valid(duration) and duration or nil, long)
    end
    return M.format_time(shown or time, long), " / " .. right
end

-- Byte after the character at byte i: a lead byte takes up to three
-- continuation bytes, any other byte (stray ones too) stands alone. So a
-- character is never split, and n characters are at most 4n bytes.
local function next_char(s, i)
    local j = i + 1
    if s:byte(i) >= 192 then
        while j <= i + 3 and (s:byte(j) or 0) >= 128 and s:byte(j) < 192 do j = j + 1 end
    end
    return j
end

function M.len(s)
    local i, n = 1, 0
    while i <= #s do i, n = next_char(s, i), n + 1 end
    return n
end

function M.prefix(s, n)
    local i = 1
    for _ = 1, n do
        if i > #s then break end
        i = next_char(s, i)
    end
    return s:sub(1, i - 1)
end

-- Capitals without depending on the locale: ASCII, Latin-1 letters and the
-- long vowels of romanised Japanese (ā ē ī ō ū).
local MACRONS = { ["\196\129"] = "\196\128", ["\196\147"] = "\196\146", ["\196\171"] = "\196\170",
                  ["\197\141"] = "\197\140", ["\197\171"] = "\197\170" }
function M.upper(s)
    s = s:gsub("[a-z]", function(c) return string.char(c:byte() - 32) end)
    s = s:gsub("\195([\160-\190])", function(c)
        if c == "\183" then return nil end -- division sign
        return "\195" .. string.char(c:byte() - 32)
    end)
    return (s:gsub("[\196\197][\128-\191]", MACRONS))
end

-- text, or its longest prefix plus "…" that is at most max_w wide. Every
-- result has been measured.
function M.fit(text, max_w, width_of)
    if max_w <= 0 then return "" end
    if width_of(text) <= max_w then return text end
    local lo, hi = 0, M.len(text) - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if width_of(M.prefix(text, mid) .. ELLIPSIS) <= max_w then lo = mid else hi = mid - 1 end
    end
    local cut = (M.prefix(text, lo):gsub("%s+$", "")) .. ELLIPSIS
    if lo == 0 and width_of(cut) > max_w then return "" end
    return cut
end

-- The title to show: media-title, without the extension when mpv fell back
-- to the file name (a file with no title tag).
function M.file_title(media_title, filename, no_ext)
    if media_title == filename and type(no_ext) == "string" and no_ext ~= "" then return no_ext end
    return media_title
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

-- Cursor x on the volume slider -> volume 0..100. The last pixel that can
-- be clicked (x1 - 1) gives 100.
function M.x_to_volume(x, lay)
    local z = lay.volume
    return math.floor(clamp((x - z.x0) / (z.x1 - 1 - z.x0), 0, 1) * 100 + 0.5)
end

local function style(st, size, opacity, bold, spacing)
    return { font = st.font, size = size * st.scale, opacity = opacity, scale = st.scale,
             bold = bold, spacing = spacing and spacing * st.scale }
end

-- ASS text for visibility v (> 0) and the time width (for M.hit).
-- st: suji's state. hover_time: the time under the cursor while it is on
-- the timeline; it replaces the position, dimmed.
function M.render(st, v, measure, hover_time)
    local s = st.scale
    local lay = M.layout(st.w, st.h, s)
    local function width(text, size, bold, spacing)
        local ass = draw.text(0, 0, 7, text, style(st, size, 1, bold, spacing))
        return measure(ass, M.len(text) * size * s * 0.55)
    end
    local function icon(name, z)
        local shape, stroke = icons.shape(name, (z.x0 + z.x1) / 2, lay.cy, ICON * s)
        return draw.stroke(shape, stroke, v, s)
    end

    local left, right = M.time_text(st.time, st.duration, st.remaining, hover_time)
    local time_w = width(((left .. right):gsub("%d", "0")), 15)
    local vz = lay.volume
    local vy0, vy1 = lay.cy - VOLUME_H * s / 2, lay.cy + VOLUME_H * s / 2
    local fill = vz.x0 + (vz.x1 - vz.x0) * clamp((tonumber(st.volume) or 0) / 100, 0, 1)
    local out = {
        icon(st.paused and "play" or "pause", lay.pause),
        draw.text(lay.time_x, lay.cy, 4, { { left, hover_time and 0.6 * v or v }, { right, v } }, style(st, 15, v)),
        icon(icons.volume_name(st.volume, st.mute), lay.mute),
        draw.rect(vz.x0 - s, vy0 - s, vz.x1 + s, vy1 + s, { color = "&H000000&", opacity = 0.45 * v, blur = s }),
        draw.rect(vz.x0, vy0, vz.x1, vy1, { opacity = 0.3 * v }),
        draw.rect(vz.x0, vy0, fill, vy1, { opacity = v }),
        icon(st.fullscreen and "windowed" or "fullscreen", lay.fullscreen),
    }

    -- Title: one line, or series above episode when both are known.
    local top, main
    if st.series and st.episode then top, main = M.upper(st.series), st.episode
    else main = st.episode or st.series or st.title or "" end
    main = M.fit(main, lay.title_w, function(t) return width(t, 20, true) end)
    out[#out + 1] = draw.text(lay.title_x, lay.title_y, 1, main, style(st, 20, v, true))
    if top then
        top = M.fit(top, lay.title_w, function(t) return width(t, 13, false, 1.5) end)
        out[#out + 1] = draw.text(lay.title_x, lay.title_y - 22 * s, 1, top, style(st, 13, 0.8 * v, false, 1.5))
    end

    return table.concat(out, "\n"), time_w
end

return M
