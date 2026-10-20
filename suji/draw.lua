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
