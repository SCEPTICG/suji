-- The controls from the bottom edge up, through main.lua and a fake mp: the
-- timeline above the row, prev and next, and the volume's slider that
-- unfolds with the cursor on the speaker.
local T = require "lib"

local function start(script_opts, props, hidpi)
    T.unload()
    props = props or {}
    props["mpv-version"] = props["mpv-version"] or "mpv v0.40.0"
    mp = T.fake_mp(props)
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = 1280, h = 720 })
    mp.fire("display-hidpi-scale", hidpi)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.fire("volume", 100)
    mp.mouse(0, 0)
    mp.advance(1)
    return mp
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function layout() return package.loaded["core.layout"] end
local function mod(name) return package.loaded["modules." .. name] end
local function box(name)
    for _, b in ipairs(layout().current().boxes) do
        if package.loaded["core.modules"].name_of(b.mod) == name then return b end
    end
end
local function x0(name) local b = box(name); return b and b.x0 end
local function last_cmd() local c = mp.commands[#mp.commands]; return c and table.concat(c, " ") end
local function click(x, y)
    mp.mouse(x, y)
    mp.commands = {}
    mp.button("press")
    return last_cmd()
end

-- From the bottom edge up: a margin, the row, the timeline -----------------------
start()
local tl = mod("timeline")
T.eq(tl.LIFT, layout().ROW_LIFT + layout().HEIGHT / 2 + tl.ZONE_HEIGHT / 2, "the grown line in the middle of its zone")
local bar = layout().bar_zone()
T.eq(bar.y0, 634, "the timeline's zone from 634")
T.eq(bar.y1, 658, "to 658")
T.eq(box("pause").y0, 658, "the row right under it")
T.eq(box("pause").y1, 702, "and 18 px over the bottom edge")
T.eq(mp.props["user-data/suji/margins"].bottom, 86, "margins: the top of the timeline")
-- At rest (v = 0): 2 px on the bottom edge, as before.
T.check(painted():find("\\1a&HD9&\\p3}m 0 2872 l 5120 2872 l 5120 2880 l 0 2880", 1, true) ~= nil,
    "at rest: the line on the bottom edge")
-- Grown (v = 1): 5 px from 643 to 648, above the row.
mp.mouse(640, 645)
mp.advance(1)
T.check(painted():find("\\1a&HA6&\\p3}m 0 2572 l 5120 2572 l 5120 2592 l 0 2592", 1, true) ~= nil,
    "grown: the line above the row")
mp.mouse(320, 645)
mp.advance(0.1)
T.check(painted():find("\\1a&H66&\\3a&H94&\\4a&HC2&}00:25{", 1, true) ~= nil, "the row's time: the time under the cursor")
-- Half way it is half way up.
mp.mouse(640, 300)
mp.advance(5)
mp.mouse(640, 645)
mp.advance(0.03)
local y = tonumber(painted():match("\\1c&HFFFFFF&\\1a&H%x%x&\\p3}m 0 (%d+) l 5120"))
T.check(y and y / 4 > 648 and y / 4 < 718, "while it grows, between the two: " .. tostring(y and y / 4))
-- A click on the grown line seeks; under the row nothing is taken.
mp.advance(1)
T.eq((click(320, 645) or ""):match("^seek"), "seek", "a click on the line above the row seeks")
mp.button("up")
T.eq(click(640, 712), nil, "under the row, the click is mpv's")
T.eq(mp.bindings["suji-bar"], nil, "and nothing is bound there")

-- HiDPI: everything twice as tall
start(nil, nil, 2)
bar = layout().bar_zone()
T.eq(bar.y0, 548, "scale 2: the timeline's zone from 548")
T.eq(bar.y1, box("pause").y0, "scale 2: on top of the row")
T.eq(mp.props["user-data/suji/margins"].bottom, 172, "scale 2: margins 172")

-- The default row: pause, prev, next, volume, time on the left -----------------------
start()
T.eq(x0("pause"), 20, "pause first")
T.eq(box("prev"), nil, "one file: no prev")
T.eq(box("next"), nil, "nor next")
T.eq(x0("volume"), 72, "the speaker after pause")
T.eq(box("volume").x1, 116, "only the speaker at rest")
T.eq(x0("time"), 124, "then the time")
T.eq(x0("fullscreen"), 1216, "fullscreen last, on the right")

-- prev and next ---------------------------------------------------------------------------
mp.fire("playlist-count", 1)
mp.fire("playlist-pos", 0)
T.check(box("prev") == nil and box("next") == nil, "a playlist of one: neither")
mp.fire("playlist-count", 3)
T.eq(box("prev"), nil, "the first entry: no prev")
T.eq(x0("next"), 72, "next where prev would be: no gap")
T.eq(x0("volume"), 124, "and the volume after it")
T.eq(click(94, 680), "playlist-next", "next runs playlist-next")
mp.fire("playlist-pos", 1)
T.eq(x0("prev"), 72, "in the middle: prev")
T.eq(x0("next"), 124, "and next")
T.eq(x0("volume"), 176, "the volume after them")
T.eq(click(94, 680), "playlist-prev", "prev runs playlist-prev")
T.eq(click(146, 680), "playlist-next", "next, next to it")
mp.fire("playlist-pos", 2)
T.eq(x0("prev"), 72, "the last entry: prev")
T.eq(box("next"), nil, "no next")
T.eq(x0("volume"), 124, "the volume closes the gap")
mp.fire("playlist-pos", -1)
T.check(box("prev") == nil and box("next") == nil, "no entry playing: neither")
mp.fire("playlist-pos", 1)
mp.fire("playlist-count", 2)
T.eq(box("next"), nil, "the list shrank: 1 is the last now")
mp.fire("playlist-count", 0)
T.check(box("prev") == nil and box("next") == nil, "an empty list: neither")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers at rest")

-- The volume unfolds with the cursor on the speaker -----------------------------------------
start()
local function width() return box("volume").x1 - box("volume").x0 end
mp.advance(5)
T.eq(width(), 44, "at rest: the speaker alone")
mp.mouse(94, 680)
mp.advance(0.05)
T.check(width() > 44 and width() < 114, "the cursor on the speaker: it unfolds (" .. width() .. ")")
T.check(mp.active_timers() > 0, "painting while it unfolds")
mp.advance(0.2)
T.eq(width(), 114, "unfolded: 44 + 64 px of slider + 6")
T.eq(x0("time"), 194, "and the time pushed 70 px to the right")
T.check(painted():find("\\1a&HB3&\\p3}m 464 2714 l 720 2714", 1, true) ~= nil, "the slider drawn, 116 to 180")
mp.advance(5)
T.eq(mp.active_timers(), 0, "unfolded and still: no timers")
T.eq(click(94, 680), "cycle mute", "a click on the speaker still mutes")
mp.mouse(150, 680)
mp.advance(1)
T.eq(width(), 114, "on the slider: still unfolded")
T.check(mp.bindings["suji-wheel-up"] ~= nil, "the wheel over the slider")
mp.bindings["suji-wheel-up"].fn()
T.eq(last_cmd(), "add volume 5", "changes the volume")
-- Away, it folds after a moment.
mp.mouse(640, 300)
mp.advance(0.3)
T.eq(width(), 114, "just left: not folded yet")
mp.mouse(150, 680)
mp.advance(1)
T.eq(width(), 114, "back in time: it stays")
mp.mouse(400, 680) -- the empty row
mp.advance(0.45)
T.check(width() < 114, "a moment after leaving: it folds")
mp.advance(0.2)
T.eq(width(), 44, "folded")
T.eq(x0("time"), 124, "the time back in its place")
T.check(painted():find("\\1a&HB3&\\p3}m 464", 1, true) == nil, "no slider")
mp.advance(5)
T.eq(mp.active_timers(), 0, "folded: no timers")
-- Not while dragging.
mp.mouse(94, 680)
mp.advance(0.3)
mp.mouse(148, 680)
mp.button("down")
T.eq(last_cmd(), "set volume 51", "a click on the slider")
mp.fire("volume", 51)
mp.mouse(640, 300)
T.eq(last_cmd(), "set volume 100", "dragged away")
mp.advance(2)
T.eq(width(), 114, "dragging away from it: it does not fold")
mp.button("up")
mp.advance(0.3)
T.eq(width(), 114, "let go: not at once")
mp.advance(0.4)
T.eq(width(), 44, "but a moment later")
-- Let go on it: it stays.
mp.mouse(94, 680)
mp.advance(0.3)
mp.mouse(148, 680)
mp.button("down")
mp.mouse(160, 680)
mp.button("up")
mp.advance(2)
T.eq(width(), 114, "let go on the slider: it stays")
-- Leaving the window folds it too.
mp.mouse(160, 680, false)
mp.advance(1)
T.eq(width(), 44, "the cursor left the window: folded")

-- A custom row keeps its own order -------------------------------------------------------------
start({ controls = "pause,time,space,volume,fullscreen" })
T.eq(x0("volume"), 1164, "volume on the right, folded")
mp.mouse(1186, 680)
mp.advance(0.3)
T.eq(x0("volume"), 1094, "unfolded leftwards, fullscreen stays")
T.eq(x0("fullscreen"), 1216, "where it was")

T.done("test_layout")
