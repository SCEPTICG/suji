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

local OUTLINE = { 4, 9, 4, 15, 8, 15, 13, 19, 13, 5, 8, 9, 4, 9 }
local WAVE1, WAVE2 = arc(12.93, 12, 5, 44.4), arc(12.93, 12, 9, 50)

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
}

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
