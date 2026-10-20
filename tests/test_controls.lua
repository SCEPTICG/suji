local T = require "lib"
local icons = require "icons"
local draw = require "draw"
local controls = require "elements.controls"

local function tt(...) local x, y = controls.time_text(...); return x .. y end

-- Icons: every one is a valid \p drawing and scales with the size
for _, name in ipairs({ "play", "pause", "volume0", "volume1", "volume2", "mute",
                        "fullscreen", "windowed" }) do
    local ass = draw.poly(icons.shape(name, 50, 50, 24), { opacity = 1, outline = draw.outline(1, 1) })
    local path = ass:match("\\p3}(.-){\\p0}$")
    T.check(path and path:match("^m %-?%d+ %-?%d+ ") ~= nil, name .. " starts with a move")
    T.check(path and path:gsub("[ml] %-?%d+ %-?%d+ ", "") == "", name .. " only has m/l points")
    local small, big = icons.shape(name, 0, 0, 22), icons.shape(name, 0, 0, 44)
    T.near(big[1][1], small[1][1] * 2, name .. " scales x")
    T.near(big[1][2], small[1][2] * 2, name .. " scales y")
    local lines, width = icons.shape(name, 50, 50, 24, "line")
    local st = draw.stroke(lines, width, 1, 1)
    local _, events = st:gsub("\n", "")
    T.eq(events, 1, name .. " line: halo and stroke")
    local lpath = st:match("[^\n]*$"):match("\\p3}(.-){\\p0}$")
    T.check(lpath and lpath:gsub("[ml] %-?%d+ %-?%d+ ?", "") == "", name .. " line only has m/l points")
    T.check(width >= 2 and width <= 2.2, name .. " line about 2 px wide")
    local _, w2 = icons.shape(name, 0, 0, 48, "line")
    T.near(w2, width * 2, name .. " line width scales")
end
T.eq(icons.shape("nope", 0, 0, 22), nil, "unknown icon")
local box = icons.shape("fullscreen", 100, 100, 24)
T.eq(box[1][1], 92, "24 px icon is centred on its point")
T.eq(icons.volume_name(0, false), "volume0", "volume 0: speaker only")
T.eq(icons.volume_name(50, false), "volume1", "medium volume: one wave")
T.eq(icons.volume_name(100, false), "volume2", "loud: two waves")
T.eq(icons.volume_name(100, true), "mute", "muted")

-- Time formatting
local ft = controls.format_time
T.eq(ft(588.9), "09:48", "mm:ss")
T.eq(ft(3725, true), "1:02:05", "h:mm:ss")
T.eq(ft(65, true), "0:01:05", "long form below an hour")
T.eq(ft(-5), "-00:05", "negative")
T.eq(ft(-0.4), "00:00", "no minus zero")
T.eq(ft(nil), "--:--", "unknown")
T.eq(ft(0 / 0, true), "-:--:--", "NaN, long")
T.eq(ft(1 / 0), "--:--", "infinite")
T.eq(tt(588.4, 1420), "09:48 / 23:40", "position / duration")
T.eq(tt(588.4, 1420, true), "09:48 / -13:52", "remaining")
T.eq(tt(4000, 7200, true), "1:06:40 / -0:53:20", "remaining, long")
T.eq(tt(10, 3600), "0:00:10 / 1:00:00", "an hour exactly is long")
T.eq(tt(nil, nil), "--:-- / --:--", "nothing known")
T.eq(tt(5, 1 / 0, true), "00:05 / --:--", "endless stream")
T.eq(tt(30, 20, true), "00:30 / -00:00", "past the end")

local a, b = controls.time_text(588.4, 1420, false, 30)
T.eq(a .. b, "00:30 / 23:40", "time under the cursor replaces the first number only")
a, b = controls.time_text(588.4, 1420, true, 30)
T.eq(b, " / -13:52", "remaining stays the real one")

-- Capitals
T.eq(controls.upper("pok\195\169mon \195\160\195\190 \195\183 \195\191"),
    "POK\195\137MON \195\128\195\158 \195\183 \195\191", "Latin-1, but not the division sign or y with diaeresis")
T.eq(controls.upper("t\197\141ky\197\141 \196\129\196\147\196\171\197\171"),
    "T\197\140KY\197\140 \196\128\196\146\196\170\197\170", "macrons")
T.eq(controls.upper("\227\129\130"), "\227\129\130", "other scripts unchanged")

-- Escaping outside text
T.eq(draw.escape("a{\\b1}b"), "a\\{\\\226\128\139b1\\}b", "braces and backslash")
T.eq(draw.escape("one\ntwo\r"), "one two ", "line breaks")
T.check(not draw.text(0, 0, 1, "x}{y", { font = "f", size = 10, opacity = 1, scale = 1 })
    :match("}x}"), "text is escaped")

-- Layout at scale 1 and 2
local l1 = controls.layout(1280, 720, 1)
T.eq(l1.cy, 680, "row centre 40 px up")
T.eq(l1.pause.x0, 20, "pause 20 px from the left")
T.eq(l1.pause.x1 - l1.pause.x0, 44, "44 px button")
T.eq(l1.pause.y1 - l1.pause.y0, 44, "44 px tall")
T.eq(l1.time_x, 72, "time 8 px after the pause button")
T.eq(l1.fullscreen.x1, 1260, "fullscreen 20 px from the right")
T.eq(l1.volume.x1, 1208, "slider 8 px before fullscreen")
T.eq(l1.volume.x1 - l1.volume.x0, 64, "64 px slider")
T.eq(l1.mute.x1, l1.volume.x0, "volume icon left of the slider")
T.eq(l1.title_x, 32, "title 32 px from the left")
T.eq(l1.title_y, 652, "title 68 px up")
local l2 = controls.layout(2560, 1440, 2)
T.eq(l2.cy, 1360, "scale 2: row centre")
T.eq(l2.pause.x1, 128, "scale 2: pause zone")
T.eq(l2.time_x, 144, "scale 2: time")
T.eq(l2.fullscreen.x0, 2432, "scale 2: fullscreen")
T.eq(l2.volume.x0, 2288, "scale 2: slider")

-- Click zones
T.eq(controls.hit(l1, 42, 680, 90), "pause", "pause")
T.eq(controls.hit(l1, 100, 680, 90), "time", "time")
T.eq(controls.hit(l1, 170, 680, 90), nil, "past the time")
T.eq(controls.hit(l1, 1120, 680, 90), "mute", "volume icon")
T.eq(controls.hit(l1, 1170, 680, 90), "volume", "slider")
T.eq(controls.hit(l1, 1240, 680, 90), "fullscreen", "fullscreen")
T.eq(controls.hit(l1, 640, 680, 90), nil, "empty middle")
T.eq(controls.hit(l1, 42, 650, 90), nil, "above the row")
T.eq(controls.hit(l2, 84, 1360, 180), "pause", "scale 2: pause")
T.eq(controls.hit(l2, 2300, 1360, 180), "volume", "scale 2: slider")
T.eq(controls.hit(l2, 1170, 680, 90), nil, "scale 2: old place is empty")

-- Slider x -> volume
T.eq(controls.x_to_volume(1144, l1), 0, "left end")
T.eq(controls.x_to_volume(1176, l1), 51, "middle")
T.eq(controls.x_to_volume(1207, l1), 100, "last clickable pixel is 100")
T.eq(controls.x_to_volume(1300, l1), 100, "past the right end")
T.eq(controls.x_to_volume(2415, l2), 100, "scale 2 last pixel")

-- Title cut: fake width of 10 px per character
local w10 = function(t) return controls.len(t) * 10 end
T.eq(controls.fit("short", 100, w10), "short", "fits")
T.eq(controls.fit("abcdefghijkl", 60, w10), "abcde\226\128\166", "cut with an ellipsis")
T.eq(controls.fit("abc def", 50, w10), "abc\226\128\166", "no space before the ellipsis")
T.eq(controls.fit("\227\129\130\227\129\132\227\129\134\227\129\136", 30, w10),
    "\227\129\130\227\129\132\226\128\166", "never splits a UTF-8 character")
T.eq(controls.fit("abc", 0, w10), "", "no room")
T.eq(controls.fit("abc", 5, w10), "", "not even the ellipsis fits")
local junk = string.rep("\128", 1000)
T.eq(controls.len(junk), 1000, "stray continuation bytes count as characters")
T.eq(#controls.prefix(junk, 200), 200, "and are cut like characters")
T.eq(#controls.prefix(string.rep("\240\128\128\128", 300), 200), 800, "never more than 4 bytes a character")
T.check(w10(controls.fit(junk, 100, w10)) <= 100, "a cut of junk is measured and fits")
T.eq(controls.len("a\195\169b"), 3, "UTF-8 length")
T.eq(controls.prefix("a\195\169b", 2), "a\195\169", "UTF-8 prefix")

-- Rendering
local st = { w = 1280, h = 720, scale = 1, time = 50, duration = 100, volume = 40, mute = false,
             fullscreen = false, paused = true, title = "Title", font = "sans-serif" }
local measure = function(_, guess) return guess end
local ass, time_w = controls.render(st, 1, measure)
T.check(time_w > 0, "time width measured")
T.check(ass:find("}00:50{", 1, true) ~= nil and ass:find("} / 01:40", 1, true) ~= nil, "time shown")
T.check(ass:find("}Title", 1, true) ~= nil, "media title shown")
local _, n = ass:gsub("\n", "")
T.eq(n + 1, 8, "icons, time, slider and title")
st.series, st.episode = "Show", "Ep 1"
ass = controls.render(st, 1, measure, 30)
T.check(ass:find("}SHOW", 1, true) ~= nil, "series in capitals")
T.check(ass:find("\\fsp1.5", 1, true) ~= nil, "series letter spacing")
T.check(ass:find("}Ep 1", 1, true) ~= nil, "episode")
T.check(ass:find("\\1a&H66&\\3a&H94&\\4a&HC2&}00:30{", 1, true) ~= nil, "time under the cursor, dimmed")
T.check(ass:find("\\an2", 1, true) == nil, "no floating tooltip")
local line = controls.render(st, 1, measure, nil, "line")
T.check(line ~= controls.render(st, 1, measure, nil, "fill"), "two icon styles")
T.check(line:find("\\1a&HFF&", 1, true) ~= nil, "line icons are strokes with no fill")
T.check(controls.render(st, 0.5, measure) ~= controls.render(st, 1, measure), "fades with v")

T.done("test_controls")
