-- Vector icons, drawn for suji on a 24x24 grid and scaled to the size
-- asked for. Each icon is a list of simple polygons that never overlap,
-- so the fill rule does not matter. No mpv dependencies.

local M = {}

local function mirror4(p)
    local out = {}
    for _, f in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        local m = {}
        for i = 1, #p, 2 do
            m[i] = f[1] == 1 and 24 - p[i] or p[i]
            m[i + 1] = f[2] == 1 and 24 - p[i + 1] or p[i + 1]
        end
        out[#out + 1] = m
    end
    return out
end

-- A 2 px wide arc around (12, 12), from -deg to +deg, as a closed band.
local function wave(r, deg)
    local outer, inner = {}, {}
    for i = 0, 6 do
        local a = math.rad(-deg + 2 * deg * i / 6)
        outer[#outer + 1], outer[#outer + 2] = 12 + (r + 1) * math.cos(a), 12 + (r + 1) * math.sin(a)
        local b = math.rad(deg - 2 * deg * i / 6)
        inner[#inner + 1], inner[#inner + 2] = 12 + (r - 1) * math.cos(b), 12 + (r - 1) * math.sin(b)
    end
    for i = 1, #inner do outer[#outer + 1] = inner[i] end
    return outer
end

-- An "x" centred on (cx, cy): a plus sign turned by 45 degrees.
local function cross(cx, cy, a, t)
    local plus = { -t, -a, t, -a, t, -t, a, -t, a, t, t, t, t, a, -t, a, -t, t, -a, t, -a, -t, -t, -t }
    local out = {}
    for i = 1, #plus, 2 do
        local x, y = plus[i], plus[i + 1]
        out[i], out[i + 1] = cx + (x - y) / math.sqrt(2), cy + (x + y) / math.sqrt(2)
    end
    return out
end

local SPEAKER = { 3, 9, 7, 9, 12, 4.5, 12, 19.5, 7, 15, 3, 15 }

local SHAPES = {
    play = { { 7.5, 4.5, 20, 12, 7.5, 19.5 } },
    pause = { { 6.5, 5, 9.5, 5, 9.5, 19, 6.5, 19 }, { 14.5, 5, 17.5, 5, 17.5, 19, 14.5, 19 } },
    volume0 = { SPEAKER },
    volume1 = { SPEAKER, wave(4.5, 45) },
    volume2 = { SPEAKER, wave(4.5, 45), wave(8, 50) },
    mute = { SPEAKER, cross(18.5, 12, 4, 1) },
    fullscreen = mirror4({ 4, 4, 10, 4, 10, 6, 6, 6, 6, 10, 4, 10 }),
    windowed = mirror4({ 10, 10, 4, 10, 4, 8, 8, 8, 8, 4, 10, 4 }),
}

-- Name of the volume icon for a level (0..100+) and the mute state.
function M.volume_name(volume, mute)
    if mute then return "mute" end
    volume = tonumber(volume) or 0
    if volume <= 0 then return "volume0" end
    return volume <= 66 and "volume1" or "volume2"
end

-- Polygons of icon `name`, `size` px wide, centred on (cx, cy). nil for an
-- unknown name.
function M.shape(name, cx, cy, size)
    local src = SHAPES[name]
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
    return out
end

return M
