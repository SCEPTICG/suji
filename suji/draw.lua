-- ASS drawing primitives. No mpv dependencies, so this can be tested with
-- plain Lua.
--
-- Every function returns one ASS event (one line of overlay data). All
-- coordinates are absolute pixels from the top-left corner of the window,
-- because the overlay resolution matches the window size.

local M = {}

-- "rrggbb" -> ASS colour "&HBBGGRR&". Returns nil for invalid input.
function M.color(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    local r, g, b = hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6)
    return ("&H%s%s%s&"):format(b, g, r):upper()
end

-- Opacity 0..1 -> ASS alpha "&HXX&" (00 is opaque, FF is transparent).
function M.alpha(opacity)
    if opacity ~= opacity then opacity = 0 end -- NaN
    opacity = math.max(0, math.min(1, opacity))
    return ("&H%02X&"):format(math.floor((1 - opacity) * 255 + 0.5))
end

-- Overall size factor: the system HiDPI scale times the user's `scale`
-- option. Missing or nonsense values fall back to 1.
function M.scale(hidpi, user)
    local function sane(n)
        n = tonumber(n)
        if not n or n ~= n or n <= 0 or n > 16 then return 1 end
        return n
    end
    return sane(hidpi) * sane(user)
end

-- Drawing commands use \p3 (coordinates divided by 4), which gives
-- quarter-pixel precision while every number stays an integer.
local function q(n)
    return math.floor(n * 4 + 0.5)
end

-- Dark thin border and soft shadow for text and icons, so they read on
-- bright scenes without a background. Faded with the element's opacity.
function M.outline(scale, opacity)
    return ("\\bord%.2f\\shad%.2f\\blur0.5\\3c&H000000&\\4c&H000000&\\3a%s\\4a%s"):format(
        1.2 * scale, scale, M.alpha(0.7 * opacity), M.alpha(0.4 * opacity))
end

local function tags(style)
    return ("{\\an7\\pos(0,0)\\bord0\\shad0\\blur%s\\1c%s\\1a%s\\p3}"):format(
        style.blur or 0, style.color or "&HFFFFFF&", M.alpha(style.opacity or 1))
end

-- Filled rectangle from (x0, y0) to (x1, y1).
-- style: { color = "&HBBGGRR&", opacity = 0..1, blur = number }
function M.rect(x0, y0, x1, y1, style)
    local a, b, c, d = q(x0), q(y0), q(x1), q(y1)
    return tags(style) ..
        ("m %d %d l %d %d l %d %d l %d %d{\\p0}"):format(a, b, c, b, c, d, a, d)
end

-- Filled polygons, all in one event: { {x1, y1, x2, y2, ...}, ... }.
-- style as for rect.
function M.poly(polys, style)
    local out = { tags(style) }
    for _, p in ipairs(polys) do
        for i = 1, #p, 2 do
            out[#out + 1] = ("%s %d %d "):format(i == 1 and "m" or "l", q(p[i]), q(p[i + 1]))
        end
    end
    out[#out + 1] = "{\\p0}"
    return table.concat(out)
end

-- Lines `width` px wide with round ends, for icons: { {x1, y1, ...}, ... }.
-- Each line is drawn there and back (no area) and libass's border draws
-- the stroke; a thicker dark copy underneath gives the halo and shadow.
function M.stroke(lines, width, opacity, scale)
    local d = {}
    for _, p in ipairs(lines) do
        d[#d + 1] = ("m %d %d"):format(q(p[1]), q(p[2]))
        for i = 3, #p, 2 do d[#d + 1] = ("l %d %d"):format(q(p[i]), q(p[i + 1])) end
        for i = #p - 3, 1, -2 do d[#d + 1] = ("l %d %d"):format(q(p[i]), q(p[i + 1])) end
    end
    local path = table.concat(d, " ")
    return ("{\\an7\\pos(0,0)\\1a&HFF&%s\\bord%.2f\\p3}%s{\\p0}\n" ..
            "{\\an7\\pos(0,0)\\1a&HFF&\\bord%.2f\\shad0\\3c&HFFFFFF&\\3a%s\\p3}%s{\\p0}"):format(
        M.outline(scale, opacity), width / 2 + 1.2 * scale, path, width / 2, M.alpha(opacity), path)
end

-- Outside text made safe for a terminal, at most max bytes: control
-- characters (C1 too, which some terminals take as escapes) and broken
-- UTF-8 become "?". Independent of the locale.
function M.printable(s, max)
    s = tostring(s):sub(1, max)
    return (s:gsub("[%z\1-\31\127]", "?"):gsub("[\128-\255][\128-\191]*", function(c)
        local b = c:byte(1)
        local n = b >= 240 and 4 or b >= 224 and 3 or 2
        if b < 194 or b >= 245 or #c < n or c:find("^\194[\128-\159]") then return ("?"):rep(#c) end
        return c:sub(1, n) .. ("?"):rep(#c - n)
    end))
end

-- Make outside text safe inside ASS: braces would open override blocks
-- and a backslash would start an escape (\N, \h...). A zero-width space
-- after the backslash keeps it literal. Line breaks become spaces.
function M.escape(text)
    return (tostring(text):gsub("\\", "\\\226\128\139"):gsub("[{}]", "\\%0"):gsub("[\r\n]", " "))
end

-- One line of white text, escaped here. t: { font, size, opacity, scale,
-- bold (plain bold: semibold falls back to regular in many fonts), spacing }.
-- an: ASS alignment. text: a string, or a list of { string, opacity } parts.
function M.text(x, y, an, text, t)
    if type(text) ~= "table" then text = { { text, t.opacity } } end
    local parts = {}
    for i, p in ipairs(text) do
        parts[i] = ("{\\1a%s\\3a%s\\4a%s}%s"):format(M.alpha(p[2]), M.alpha(0.7 * p[2]),
            M.alpha(0.4 * p[2]), M.escape(p[1]))
    end
    return ("{\\an%d\\pos(%.1f,%.1f)\\q2\\fn%s\\fs%.1f\\b%d\\fsp%.1f\\1c&HFFFFFF&%s}%s"):format(
        an, x, y, t.font, t.size, t.bold and 1 or 0, t.spacing or 0,
        M.outline(t.scale, t.opacity), table.concat(parts))
end

-- Filled circle made of four cubic Bezier curves.
local KAPPA = 0.5523
function M.circle(cx, cy, r, style)
    local k = r * KAPPA
    local p = function(x, y) return ("%d %d"):format(q(x), q(y)) end
    return tags(style) .. table.concat({
        "m ", p(cx, cy - r),
        " b ", p(cx + k, cy - r), " ", p(cx + r, cy - k), " ", p(cx + r, cy),
        " b ", p(cx + r, cy + k), " ", p(cx + k, cy + r), " ", p(cx, cy + r),
        " b ", p(cx - k, cy + r), " ", p(cx - r, cy + k), " ", p(cx - r, cy),
        " b ", p(cx - r, cy - k), " ", p(cx - k, cy - r), " ", p(cx, cy - r),
        "{\\p0}",
    })
end

return M
