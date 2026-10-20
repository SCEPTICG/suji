-- The row: icons, text helpers, the layout engine and the modules of the
-- row, drawn through the core's ctx against a fake mp.
local T = require "lib"
mp = T.fake_mp()
local icons = require "core.icons"
local draw = require "core.draw"
local text = require "core.text"
local layout = require "core.layout"
local modules = require "core.modules"
local state = require "core.state"
local time = require "modules.time"
local volume = require "modules.volume"
local pause = require "modules.pause"
local fullscreen = require "modules.fullscreen"
local command = require "modules.command"

local function tt(...) local x, y = time.time_text(...); return x .. y end

-- Icons: every one is a valid \p stroke and scales with the size
for _, name in ipairs({ "play", "pause", "volume0", "volume1", "volume2", "mute",
                        "fullscreen", "windowed" }) do
    local small, big = icons.shape(name, 0, 0, 22), icons.shape(name, 0, 0, 44)
    T.near(big[1][1], small[1][1] * 2, name .. " scales x")
    T.near(big[1][2], small[1][2] * 2, name .. " scales y")
    local lines, width = icons.shape(name, 50, 50, 24)
    local st = draw.stroke(lines, width, 1, 1)
    local _, events = st:gsub("\n", "")
    T.eq(events, 1, name .. " line: halo and stroke")
    local lpath = st:match("[^\n]*$"):match("\\p3}(.-){\\p0}$")
    T.check(lpath and lpath:gsub("[ml] %-?%d+ %-?%d+ ?", "") == "", name .. " line only has m/l points")
    T.check(width >= 2 and width <= 2.2, name .. " line about 2 px wide")
    local _, w2 = icons.shape(name, 0, 0, 48)
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
local ft = time.format_time
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

local a, b = time.time_text(588.4, 1420, false, 30)
T.eq(a .. b, "00:30 / 23:40", "time under the cursor replaces the first number only")
a, b = time.time_text(588.4, 1420, true, 30)
T.eq(b, " / -13:52", "remaining stays the real one")

-- Capitals
T.eq(text.upper("pok\195\169mon \195\160\195\190 \195\183 \195\191"),
    "POK\195\137MON \195\128\195\158 \195\183 \195\191", "Latin-1, but not the division sign or y with diaeresis")
T.eq(text.upper("t\197\141ky\197\141 \196\129\196\147\196\171\197\171"),
    "T\197\140KY\197\140 \196\128\196\146\196\170\197\170", "macrons")
T.eq(text.upper("\227\129\130"), "\227\129\130", "other scripts unchanged")

-- Escaping outside text
T.eq(draw.escape("a{\\b1}b"), "a\\{\\\226\128\139b1\\}b", "braces and backslash")
T.eq(draw.escape("one\ntwo\r"), "one two ", "line breaks")
T.check(not draw.text(0, 0, 1, "x}{y", { font = "f", size = 10, opacity = 1, scale = 1 })
    :match("}x}"), "text is escaped")

-- Layout of the default row at scale 1 and 2. The time is 90 px wide here.
local function default_row(s, time_w)
    return { { mod = pause, width = 44 * s }, { mod = time, width = time_w * s }, { space = true },
             { mod = volume, width = 108 * s }, { mod = fullscreen, width = 44 * s } }
end
local function box_of(placed, mod) return layout.find(placed, mod) end
local l1 = layout.place(default_row(1, 90), { w = 1280, h = 720, scale = 1 })
local p1, t1, v1, f1 = box_of(l1, pause), box_of(l1, time), box_of(l1, volume), box_of(l1, fullscreen)
T.eq(p1.cy, 680, "row centre 40 px up")
T.eq(p1.x0, 20, "pause 20 px from the left")
T.eq(p1.x1 - p1.x0, 44, "44 px button")
T.eq(p1.y1 - p1.y0, 44, "44 px tall")
T.eq(t1.x0, 72, "time 8 px after the pause button")
T.eq(f1.x1, 1260, "fullscreen 20 px from the right")
T.eq(v1.x1, 1208, "slider 8 px before fullscreen")
T.eq(v1.x1 - (v1.x0 + 44), 64, "64 px slider")
T.eq(v1.x0, 1100, "volume icon left of the slider")
T.eq(l1.right_x0, 1100, "the right part starts at the volume icon")
local l2 = layout.place(default_row(2, 90), { w = 2560, h = 1440, scale = 2 })
T.eq(box_of(l2, pause).cy, 1360, "scale 2: row centre")
T.eq(box_of(l2, pause).x1, 128, "scale 2: pause zone")
T.eq(box_of(l2, time).x0, 144, "scale 2: time")
T.eq(box_of(l2, fullscreen).x0, 2432, "scale 2: fullscreen")
T.eq(box_of(l2, volume).x0 + 88, 2288, "scale 2: slider")

-- Click zones
local function at(l, x, y) local z = layout.hit(l, x, y); return z and z.mod end
T.eq(at(l1, 42, 680), pause, "pause")
T.eq(at(l1, 100, 680), time, "time")
T.eq(at(l1, 170, 680), nil, "past the time")
T.eq(at(l1, 1120, 680), volume, "volume icon")
T.eq(at(l1, 1170, 680), volume, "slider")
T.eq(at(l1, 1240, 680), fullscreen, "fullscreen")
T.eq(at(l1, 640, 680), nil, "empty middle")
T.eq(at(l1, 42, 650), nil, "above the row")
T.eq(at(l2, 84, 1360), pause, "scale 2: pause")
T.eq(at(l2, 2300, 1360), volume, "scale 2: slider")
T.eq(at(l2, 1170, 680), nil, "scale 2: old place is empty")
local withbar = layout.place(default_row(1, 90), { w = 1280, h = 720, scale = 1 })
withbar.bar = { mod = "tl", bar = true, x0 = 0, y0 = 696, x1 = 1280, y1 = 720 }
T.eq(layout.hit(withbar, 42, 700).mod, "tl", "the timeline's zone comes first")
T.eq(layout.hit(withbar, 42, 695).mod, pause, "just above it, the button")

-- Slider x -> volume
T.eq(volume.x_to_volume(1144, 1144, 1208), 0, "left end")
T.eq(volume.x_to_volume(1176, 1144, 1208), 51, "middle")
T.eq(volume.x_to_volume(1207, 1144, 1208), 100, "last clickable pixel is 100")
T.eq(volume.x_to_volume(1300, 1144, 1208), 100, "past the right end")
T.eq(volume.x_to_volume(2415, 2288, 2416), 100, "scale 2 last pixel")

-- The layout engine with other rows
local function xs(l)
    local t = {}
    for _, bx in ipairs(l.boxes) do t[#t + 1] = bx.x0 .. "-" .. bx.x1 end
    return table.concat(t, " ")
end
local A, B, C, D = {}, {}, {}, {}
local g = { w = 1000, h = 600, scale = 1 }
T.eq(xs(layout.place({ { mod = A, width = 44 }, { mod = B, width = 44 } }, g)), "20-64 72-116",
    "no space: all on the left, 8 px apart")
T.eq(layout.place({ { mod = A, width = 44 } }, g).right_x0, 980, "no space: the title goes up to the margin")
T.eq(xs(layout.place({ { mod = A, width = 44 }, { gap = true }, { mod = B, width = 44 } }, g)), "20-64 88-132",
    "a gap is 8 px more, 24 px between its neighbours")
T.eq(xs(layout.place({ { space = true }, { mod = A, width = 44 }, { mod = B, width = 44 } }, g)), "884-928 936-980",
    "space first: all on the right")
T.eq(xs(layout.place({ { mod = A, width = 40 }, { space = true }, { mod = B, width = 40 }, { space = true },
    { mod = C, width = 40 } }, g)), "20-60 480-520 940-980", "two spaces share the free width")
T.eq(xs(layout.place({ { mod = A, width = 40 }, { space = true }, { space = true }, { mod = B, width = 40 } }, g)),
    "20-60 940-980", "two spaces in a row")
local l3 = layout.place({ { mod = A, width = 40 }, { space = true }, { gap = true }, { mod = B, width = 40 },
    { mod = C, width = 44 }, { space = true }, { mod = D, width = 20 } }, g)
T.eq(xs(l3), "20-60 472-512 520-564 960-980", "gaps and two spaces")
T.eq(l3.right_x0, 472, "the right part starts after the first space")
local l4 = layout.place({ { mod = A, width = 88 } }, { w = 1000, h = 600, scale = 2 })
T.eq(xs(l4), "40-128", "scale 2 margins and widths")
T.eq(l4.boxes[1].cy, 520, "scale 2 row centre")
T.eq(#layout.place({}, g).boxes, 0, "an empty row")

-- The modules of the row through the core, with the default controls
modules.init()
modules.set_controls("pause,time,space,volume,fullscreen")
state.w, state.h, state.scale, state.time, state.duration = 1280, 720, 1, 50, 100
state.paused, state.title, state.font = true, "Title", "sans-serif"
mp.fire("volume", 40)
mp.fire("mute", false)
mp.fire("fullscreen", false)
local ctx = modules.ctx

local function row_ass(v)
    local placed, out = layout.current(), {}
    for _, bx in ipairs(placed.boxes) do out[#out + 1] = modules.call(bx.mod, "render", ctx, bx, v) end
    out[#out + 1] = modules.call(modules.title, "render", ctx, { x0 = 0, y0 = 0, x1 = placed.right_x0, y1 = 0 }, v)
    return table.concat(out, "\n"), placed
end
local ass, placed = row_ass(1)
local tb = layout.find(placed, time)
T.check(tb.x1 - tb.x0 > 0, "time width measured")
T.eq(tb.x0, 72, "time where it was")
T.check(ass:find("}00:50{", 1, true) ~= nil and ass:find("} / 01:40", 1, true) ~= nil, "time shown")
T.check(ass:find("}Title", 1, true) ~= nil, "media title shown")
T.check(ass:find("\\pos(32.0,652.0)", 1, true) ~= nil, "title 32 px from the left, 68 px up")
local _, n = ass:gsub("\n", "")
T.eq(n + 1, 11, "icons (two events each), time, slider and title")
state.series, state.episode = "Show", "Ep 1"
ctx.hover_time = function() return 30 end
ass = row_ass(1)
T.check(ass:find("}SHOW", 1, true) ~= nil, "series in capitals")
T.check(ass:find("\\fsp1.5", 1, true) ~= nil, "series letter spacing")
T.check(ass:find("}Ep 1", 1, true) ~= nil, "episode")
T.check(ass:find("\\1a&H66&\\3a&H94&\\4a&HC2&}00:30{", 1, true) ~= nil, "time under the cursor, dimmed")
T.check(ass:find("\\an2", 1, true) == nil, "no floating tooltip")
ctx.hover_time = function() return nil end
local line = row_ass(1)
local _, strokes = line:gsub("\\1a&HFF&", "")
T.eq(strokes, 6, "the three icons are strokes with no fill (halo and line each)")
T.check(row_ass(0.5) ~= row_ass(1), "fades with v")

-- A long title stops before the right part of the row
state.series, state.episode, state.title = nil, nil, ("w"):rep(500)
local cut = row_ass(1):match("}(w+\226\128\166)$")
T.check(cut ~= nil, "a long title is cut")
T.check(cut and #cut - 3 <= math.floor((1100 - 56) / (20 * 0.55)), "and fits before the volume")
state.title = "Title"

-- Volume: the icon mutes, the slider sets the volume and holds the mouse
local vb = layout.find(layout.current(), volume)
mp.commands = {}
T.eq(volume.press(ctx, vb, 1120, 680), nil, "the icon does not hold the mouse")
T.eq(table.concat(mp.commands[#mp.commands], " "), "cycle mute", "the icon mutes")
T.eq(volume.press(ctx, vb, 1176, 680), true, "the slider holds the mouse")
T.eq(table.concat(mp.commands[#mp.commands], " "), "set volume 51", "click on the slider")
volume.move(ctx, vb, 1100, 600)
T.eq(table.concat(mp.commands[#mp.commands], " "), "set volume 0", "drag on the slider")
mp.fire("volume", 51)
local before = #mp.commands
volume.move(ctx, vb, 1176, 600)
T.eq(#mp.commands, before, "same volume: no command")
T.check(pause.press(ctx) == nil and fullscreen.press(ctx) == nil, "buttons do not hold the mouse")

-- command: a known icon, or the initial of an unknown one
local known = command.new({ icon = "pause", command = "set pause yes" })
local unknown = command.new({ icon = "zap", command = "show-text hi", text = "Say hi" })
local cb = { x0 = 100, y0 = 658, x1 = 144, y1 = 702, cy = 680 }
T.eq(known.width(ctx), 44, "a command button is a button")
T.check(known.render(ctx, cb, 1):find("\\p3}", 1, true) ~= nil, "known icon drawn as lines")
T.check(unknown.render(ctx, cb, 1):find("\\an5\\pos(122.0,680.0)", 1, true) ~= nil, "unknown icon: centred letter")
T.check(unknown.render(ctx, cb, 1):find("}Z$") ~= nil, "unknown icon: its initial, in capitals")
T.check(not unknown.render(ctx, cb, 1):find("Say hi", 1, true), "the text is kept, not drawn")
T.eq(unknown.text, "Say hi", "the text is kept")
mp.commands = {}
T.eq(unknown.press(ctx), nil, "a command button does not hold the mouse")
T.eq(mp.commands[1] and mp.commands[1][1], "show-text hi", "runs its command with mp.command")

T.done("test_row")
