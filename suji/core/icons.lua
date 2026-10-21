-- Vector icons on a 24x24 grid, scaled to the size asked for: open lines
-- about 2 px wide, drawn with draw.stroke. No mpv dependencies.

local M = {}

-- An arc around (cx, cy) from -deg to +deg, as a line of points.
local function arc(cx, cy, r, deg)
    local p = {}
    for i = 0, 8 do
        local a = math.rad(-deg + 2 * deg * i / 8)
        p[#p + 1], p[#p + 2] = cx + r * math.cos(a), cy + r * math.sin(a)
    end
    return p
end

-- An arc from angle a0 to a1 in degrees (0 is to the right, 90 down), in
-- n steps (8 by default); with ry, part of an ellipse r wide, ry high.
local function arc_from(cx, cy, r, a0, a1, n, ry)
    n, ry = n or 8, ry or r
    local p = {}
    for i = 0, n do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        p[#p + 1], p[#p + 2] = cx + r * math.cos(a), cy + ry * math.sin(a)
    end
    return p
end

local function circle(cx, cy, r) return arc_from(cx, cy, r, 0, 360, 16) end

-- A closed line through points at radius r0 and r1 in turn, every 180/n
-- degrees from the top: a star with n points.
local function star(cx, cy, r0, r1, n)
    local p = {}
    for i = 0, 2 * n do
        local a, r = math.rad(-90 + 180 * i / n), i % 2 == 0 and r0 or r1
        p[#p + 1], p[#p + 2] = cx + r * math.cos(a), cy + r * math.sin(a)
    end
    return p
end

-- A closed toothed ring: n teeth reaching r1 over a ring of radius r0.
local function gear(cx, cy, r0, r1, n)
    local p = {}
    for t = 0, n - 1 do
        for _, d in ipairs({ { -13, r0 }, { -7, r1 }, { 7, r1 }, { 13, r0 } }) do
            local a = math.rad(360 * t / n + d[1])
            p[#p + 1], p[#p + 2] = cx + d[2] * math.cos(a), cy + d[2] * math.sin(a)
        end
    end
    p[#p + 1], p[#p + 2] = p[1], p[2]
    return p
end

local OUTLINE = { 4, 9, 4, 15, 8, 15, 13, 19, 13, 5, 8, 9, 4, 9 }
local WAVE1, WAVE2 = arc(12.93, 12, 5, 44.4), arc(12.93, 12, 9, 50)
-- A round palette with a notch for the thumb at the bottom right.
local PALETTE = arc_from(12, 12, 9, 75, 390, 14)
for _, v in ipairs({ 16, 15.5, 14.5, 17.5, PALETTE[1], PALETTE[2] }) do PALETTE[#PALETTE + 1] = v end

-- Lines, and the stroke width on the grid.
local LINES = {
    play = { { 7.5, 5, 19, 12, 7.5, 19, 7.5, 5 } },
    pause = { { 8, 5, 8, 19 }, { 16, 5, 16, 19 }, width = 2.2 },
    volume0 = { OUTLINE },
    volume1 = { OUTLINE, WAVE1 },
    volume2 = { OUTLINE, WAVE1, WAVE2 },
    mute = { OUTLINE, { 16, 9.5, 21, 14.5 }, { 21, 9.5, 16, 14.5 } },
    fullscreen = { { 4, 9, 4, 4, 9, 4 }, { 20, 9, 20, 4, 15, 4 }, { 4, 15, 4, 20, 9, 20 }, { 20, 15, 20, 20, 15, 20 } },
    windowed = { { 9, 4, 9, 9, 4, 9 }, { 15, 4, 15, 9, 20, 9 }, { 9, 20, 9, 15, 4, 15 }, { 15, 20, 15, 15, 20, 15 } },
    -- The buttons with menus.
    subtitles = { { 3, 5, 21, 5, 21, 19, 3, 19, 3, 5 }, { 7, 11.5, 10, 11.5 }, { 13, 11.5, 17, 11.5 },
                  { 7, 15, 14, 15 }, { 16.6, 15, 17.4, 15 } },
    audio = { arc_from(12, 13, 8, 180, 360), { 4, 13, 4, 19, 7.5, 19, 7.5, 14, 4, 14 },
              { 20, 13, 20, 19, 16.5, 19, 16.5, 14, 20, 14 } },
    playlist = { { 4.1, 7, 4.9, 7 }, { 4.1, 12, 4.9, 12 }, { 4.1, 17, 4.9, 17 },
                 { 9, 7, 20, 7 }, { 9, 12, 20, 12 }, { 9, 17, 16, 17 } },
    more = { { 4.6, 12, 5.4, 12 }, { 11.6, 12, 12.4, 12 }, { 18.6, 12, 19.4, 12 }, width = 2.2 },
    -- For other scripts' buttons and menus (see docs/api.md).
    text_fields = { { 3, 5, 12, 5 }, { 7.5, 5, 7.5, 19 }, { 15, 9, 21, 9 }, { 15, 14, 21, 14 }, { 15, 19, 19, 19 } },
    auto_awesome = { { 10, 7, 11.5, 12.5, 17, 14, 11.5, 15.5, 10, 21, 8.5, 15.5, 3, 14, 8.5, 12.5, 10, 7 },
                     { 18, 3, 18, 9 }, { 15, 6, 21, 6 } },
    speed = { arc_from(12, 14, 8.5, 150, 390, 12), { 12, 14, 16, 9.5 } },
    history = { arc_from(12, 12, 8, 500, 200, 12), { 2.7, 5.4, 4.5, 9.3, 8.3, 7.5 }, { 12, 7.5, 12, 12, 15, 14 } },
    palette = { PALETTE, { 7.6, 10.5, 8.4, 10.5 }, { 11.6, 7, 12.4, 7 }, { 15.6, 8.5, 16.4, 8.5 }, { 7.1, 14.5, 7.9, 14.5 } },
    system_update_alt = { { 12, 3.5, 12, 14 }, { 8, 10, 12, 14, 16, 10 }, { 4, 13, 4, 20, 20, 20, 20, 13 } },
    star = { star(12, 12.8, 9.5, 4, 5) },
    language = { circle(12, 12, 9), arc_from(12, 12, 3.8, 0, 360, 16, 9), { 3, 12, 21, 12 } },
    settings = { gear(12, 12, 6.8, 9.3, 8), circle(12, 12, 2.8) },
    info = { circle(12, 12, 9), { 12, 11, 12, 16.5 }, { 12, 7.6, 12, 8.4 } },
    screenshot = { { 3, 8, 3, 19, 21, 19, 21, 8, 16, 8, 14.5, 5.5, 9.5, 5.5, 8, 8, 3, 8 }, arc_from(12, 13.5, 3.5, 0, 360, 12) },
    next = { { 6, 6, 14.5, 12, 6, 18, 6, 6 }, { 18, 6, 18, 18 } },
    prev = { { 18, 6, 9.5, 12, 18, 18, 18, 6 }, { 6, 6, 6, 18 } },
    close = { { 6, 6, 18, 18 }, { 18, 6, 6, 18 } },
    check = { { 4.5, 12.5, 9.5, 17.5, 19.5, 7 } },
}

-- Every icon name, sorted.
function M.names()
    local t = {}
    for name in pairs(LINES) do t[#t + 1] = name end
    table.sort(t)
    return t
end

-- Name of the volume icon for a level (0..100+) and the mute state.
function M.volume_name(volume, mute)
    if mute then return "mute" end
    volume = tonumber(volume) or 0
    if volume <= 0 then return "volume0" end
    return volume <= 66 and "volume1" or "volume2"
end

-- Lines of icon `name`, `size` px wide, centred on (cx, cy), and the
-- stroke width in px. nil for an unknown name.
function M.shape(name, cx, cy, size)
    local src = LINES[name]
    if not src then return nil end
    local k, x0, y0 = size / 24, cx - size / 2, cy - size / 2
    local out = {}
    for n, p in ipairs(src) do
        local s = {}
        for i = 1, #p, 2 do
            s[i], s[i + 1] = x0 + p[i] * k, y0 + p[i + 1] * k
        end
        out[n] = s
    end
    return out, (src.width or 2) * k
end

return M
