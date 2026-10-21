-- The menu service and the five menus, through main.lua and a fake mp.
local T = require "lib"

local W, H = 1280, 720
local Y1 = 646 -- bottom of a menu at scale 1: 12 px above the row's zones (658)
local BG = 6   -- the panel behind it reaches this much above and below the items

-- The playlist list in props as mpv has it: the whole list, and what suji
-- reads entry by entry to count them.
local function playlist_props(props, list)
    props.playlist, props["playlist-count"], props["playlist-current-pos"] = list, #list, -1
    for i, e in ipairs(list) do
        props[("playlist/%d/filename"):format(i - 1)] = e.filename
        if e.current then props["playlist-current-pos"] = i - 1 end
    end
end

local function start(props, script_opts)
    T.unload()
    props = props or {}
    if props.playlist then playlist_props(props, props.playlist) end
    props["mpv-version"] = props["mpv-version"] or "mpv v0.40.0"
    props["osd-dimensions"], props.duration, props.pause = { w = W, h = H }, 100, true
    props["time-pos"], props.volume = 50, 100
    -- Two editions, so more has something to offer and is in the row.
    if props["edition-list"] == nil then props["edition-list"] = { { id = 0 }, { id = 1 } } end
    if props["edition-list/count"] == nil then
        props["edition-list/count"] = type(props["edition-list"]) == "table" and #props["edition-list"] or 0
    end
    mp = T.fake_mp(props)
    mp.async_observe = true -- first values arrive later, as in mpv
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = W, h = H })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", true)
    mp.fire("time-pos", 50)
    mp.fire("volume", 100)
    for _, p in ipairs({ "track-list", "chapters", "playlist", "idle-active" }) do
        if props[p] ~= nil then mp.fire(p, props[p]) end
    end
    mp.mouse(640, 300)
    mp.advance(1)
    return mp
end

-- A new playlist: mpv says it changed, and the count runs once after.
local function set_playlist(list)
    playlist_props(mp.props, list)
    mp.fire("playlist")
    mp.advance(0)
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function cmd(c) return c and table.concat(c, " ") end
local function last_cmd() return cmd(mp.commands[#mp.commands]) end
local function mod(name) return package.loaded["modules." .. name] end
local function menu() return package.loaded["core.menu"] end
local function ctx_of(name) return package.loaded["core.modules"].ctx_of(mod(name)) end
local function box_of(name)
    local l = package.loaded["core.layout"]
    return l.find(l.current(), mod(name))
end
local function count(s, pat)
    local _, n = s:gsub(pat, "")
    return n
end
local function logs(level, pattern)
    local t = {}
    for _, l in ipairs(mp.logs) do
        if l[1] == level and (not pattern or tostring(l[2]):find(pattern, 1, true)) then t[#t + 1] = l[2] end
    end
    return t
end
-- y (in px) of the top of each active mark: the 2 px wide accent lines.
local function marks(ass)
    local t = {}
    for x0, y0, x1 in (ass or painted()):gmatch("\\1c&HFFFFFF&\\1a&H00&\\p3}m (%d+) (%d+) l (%d+)") do
        if tonumber(x1) - tonumber(x0) == 8 then t[#t + 1] = tonumber(y0) / 4 end
    end
    return t
end
local function suji_bindings()
    local t = {}
    for name in pairs(mp.bindings) do if name:find("^suji%-") then t[#t + 1] = name end end
    table.sort(t)
    return table.concat(t, " ")
end

-- Click at (x, y); returns the commands it sent, joined.
local function click(x, y)
    mp.mouse(x, y)
    mp.commands = {}
    mp.button("press")
    local t = {}
    for i, c in ipairs(mp.commands) do t[i] = cmd(c) end
    mp.advance(1)
    return table.concat(t, " | ")
end
local function open(name)
    local b = assert(box_of(name), name .. " is in the row")
    return click((b.x0 + b.x1) / 2, b.cy)
end
-- Centre of visible row k of an open menu of n items (no title) on button
-- name, and an x inside it.
local function row(name, k, n)
    local rows = math.min(n, 20)
    return box_of(name).x0 + 40, Y1 - rows * 30 + (k - 0.5) * 30
end

local function items(n, extra)
    local t = {}
    for i = 1, n do
        t[i] = { title = "Item " .. i, value = { "show-text", "item " .. i } }
        for k, v in pairs(extra and extra(i) or {}) do t[i][k] = v end
    end
    return t
end
local function shown(i) return painted():find("}Item " .. i .. "$") ~= nil or painted():find("}Item " .. i .. "\n", 1, true) ~= nil end

local SUBS = {
    { type = "video", id = 1, selected = true },
    { type = "audio", id = 1, lang = "jpn", selected = true },
    { type = "sub", id = 1, title = "English", lang = "eng", default = true },
    { type = "sub", id = 2, lang = "spa", forced = true, selected = true },
    { type = "sub", id = 3, external = true },
}

-- Subtitles: the list, the marks and the exact commands ------------------------
start({ ["track-list"] = SUBS })
T.check(box_of("subtitles") ~= nil and box_of("more") ~= nil, "subtitles and more in the default row")
T.eq(box_of("audio"), nil, "one audio track: no audio button")
T.eq(box_of("playlist"), nil, "no chapters, one entry: no playlist button")
T.eq(box_of("volume").x0, 1100, "the volume stays where it was")
T.eq(open("subtitles"), "", "opening sends no command")
T.check(menu().is_open(mod("subtitles")), "the subtitles menu is open")
local p = painted()
T.check(p:find("}Off", 1, true) and p:find("}English", 1, true) and p:find("}spa", 1, true) and p:find("}Track 3", 1, true),
    "Off, title, language, Track N")
T.check(p:find("}eng, default", 1, true) and p:find("}forced", 1, true) and p:find("}external", 1, true), "hints")
T.check(not p:find("}spa, forced", 1, true), "the language is not repeated when it is the title")
T.eq(#marks(p), 1, "one active mark")
T.eq(marks(p)[1], Y1 - 4 * 30 + 75 - 7, "on the selected track")
local mx, my = row("subtitles", 3, 4)
T.check(menu().contains(mx, my), "the menu is above the button")
T.check(not menu().contains(mx, 658), "and not over the row")
T.eq(click(row("subtitles", 1, 4)), "set sid no", "Off")
T.check(not menu().is_open(), "a choice closes the menu")
open("subtitles")
T.eq(click(row("subtitles", 2, 4)), "set sid 1", "a track by its id")
open("subtitles")
T.eq(click(row("subtitles", 4, 4)), "set sid 3", "the last track")
mp.advance(1)
T.check(not painted():find("}Off", 1, true), "closed: not drawn")
T.eq(suji_bindings(), "", "closed, cursor still where the menu was: no binding of suji left")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers")

-- The active mark follows a change made elsewhere, with the menu open
open("subtitles")
local n_upd = #mp.updates
local list = { SUBS[1], SUBS[2], SUBS[3], { type = "sub", id = 2, lang = "spa", forced = true }, SUBS[5] }
mp.props["track-list"] = list
mp.fire("track-list", list)
mp.advance(0.01)
T.check(#mp.updates > n_upd, "repainted at once")
T.check(painted():find("\\clip", 1, true) == nil, "no animation for an update")
T.eq(marks()[1], Y1 - 4 * 30 + 15 - 7, "no subtitles now: Off is marked")
menu().close()

-- Opening: upwards, a fade, then still -------------------------------------------
start({ ["track-list"] = SUBS })
local b = box_of("subtitles")
mp.mouse((b.x0 + b.x1) / 2, b.cy)
mp.button("press")
mp.advance(0.05)
T.check(painted():find("\\clip", 1, true) ~= nil, "unfolding: clipped while it opens")
mp.advance(1)
T.check(painted():find("\\clip", 1, true) == nil, "open: no clip")
mp.mouse(640, 300)
mp.advance(10)
T.eq(mp.active_timers(), 0, "an open menu standing still leaves no timers")
mp.mouse(640, 300, false) -- out of the window
mp.advance(10)
T.check(painted():find("}Off", 1, true) ~= nil, "still open and drawn with the mouse gone and still")
T.check(painted():find("}00:50", 1, true) ~= nil, "and the controls stay")
mp.fire("pause", false)
mp.advance(10)
T.check(painted():find("}00:50", 1, true) ~= nil, "playing: the controls stay while it is open")
T.eq(mp.active_timers(), 0, "still no timers")
menu().close()
mp.advance(0.05)
T.check(painted():find("\\clip", 1, true) ~= nil, "closing fades out too")
mp.advance(1)
T.eq(mp.active_timers(), 0, "and stops")
T.check(painted():find("}00:50", 1, true) == nil, "closed: the controls hide again")

-- Esc, the keys, and no bindings once closed -----------------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
T.eq(suji_bindings(), "suji-bar suji-bar-dbl suji-menu-down suji-menu-enter suji-menu-esc suji-menu-kp_enter suji-menu-up",
    "the keys and the mouse while open")
T.eq(mp.bindings["suji-menu-up"].flags.repeatable, true, "arrows repeat")
mp.bindings["suji-menu-esc"].fn()
T.check(not menu().is_open(), "Esc closes")
T.eq(suji_bindings(), "suji-bar suji-bar-dbl", "only the button's, under the cursor")
mp.mouse(640, 300)
T.eq(suji_bindings(), "", "no binding left")
open("subtitles")
mp.mouse(640, 300) -- off the menu
mp.commands = {}
mp.bindings["suji-menu-down"].fn() -- the first key shows the cursor on the active item (spa)
mp.advance(0.1)
T.eq(tonumber(painted():match("\\1a&HE6&\\p3}m %d+ (%d+)")), (Y1 - 4 * 30 + 60) * 4, "the cursor is on the active item")
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-enter"].fn()
T.eq(last_cmd(), "set sid 3", "Down and Enter choose the next track")
open("subtitles")
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-enter"].fn()
T.eq(last_cmd(), "set sid no", "Up stops at the first item")

-- The keys never stop on what cannot be chosen
start()
ctx_of("more").open_menu({ type = "x", items = {
    { title = "Group", selectable = false }, { title = "A", value = { "show-text", "a" } },
    { title = "B", value = { "show-text", "b" } } } }, box_of("more"))
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-enter"].fn()
T.eq(last_cmd(), "show-text a", "Up on a header first: the first item that can be chosen")
ctx_of("more").open_menu({ type = "x", items = {
    { title = "Group", selectable = false }, { title = "A", value = { "show-text", "a" } },
    { title = "Other", selectable = false } } }, box_of("more"))
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-up"].fn()
mp.bindings["suji-menu-up"].fn()
mp.mouse(640, 300)
mp.advance(0.1)
T.eq(tonumber(painted():match("\\1a&HE6&\\p3}m %d+ (%d+)")), (Y1 - 90 + 30) * 4, "the cursor stays on A")
mp.commands = {}
mp.bindings["suji-menu-enter"].fn()
T.eq(last_cmd(), "show-text a", "and Enter takes it")
ctx_of("more").open_menu({ type = "x", items = { { title = "Only a header", selectable = false } } }, box_of("more"))
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-up"].fn()
mp.advance(0.1)
T.check(painted():find("\\1a&HE6&", 1, true) == nil, "nothing to choose: no cursor")
menu().close(true)

-- Hover --------------------------------------------------------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
local hx, hy = row("subtitles", 2, 4)
mp.mouse(hx, hy)
mp.advance(0.1)
local hl = painted():match("\\1a&HE6&\\p3}m %d+ (%d+)")
T.eq(tonumber(hl), (Y1 - 4 * 30 + 30) * 4, "the item under the cursor is highlighted")
mp.mouse(hx, hy + 30)
mp.advance(0.1)
T.eq(tonumber(painted():match("\\1a&HE6&\\p3}m %d+ (%d+)")), (Y1 - 4 * 30 + 60) * 4, "and follows it")
mp.mouse(640, 300)
mp.advance(0.1)
T.check(painted():find("\\1a&HE6&", 1, true) == nil, "off the menu: no highlight")

-- A click outside closes and does nothing else ---------------------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
T.eq(click(box_of("subtitles").x0 + 40, Y1 + BG - 2), "", "a click on the panel's edge: nothing")
T.check(menu().is_open(), "and the menu stays open")
menu().close(true)
open("subtitles")
T.eq(click(640, 710), "", "a click on the timeline: no seek")
T.check(not menu().is_open(), "and the menu closed")
open("subtitles")
T.eq(click(42, 680), "", "on the pause button: no pause")
T.check(not menu().is_open(), "closed")
open("subtitles")
T.eq(click(1240, 680), "", "on another button: nothing")
open("subtitles")
T.eq(click(640, 300), "", "in the middle of the video: nothing")
T.check(mp.bindings["suji-bar-dbl"] == nil, "double clicks on the video are mpv's again")
open("subtitles")
T.check(menu().is_open(), "open")
T.eq(open("subtitles"), "", "the same button closes it")
T.check(not menu().is_open(), "closed")
mp.advance(1)
T.check(not menu().is_open(), "and it does not open again")

-- A double click on an entry does not reach mpv (it would toggle fullscreen)
start({ ["track-list"] = SUBS })
open("subtitles")
local dx, dy = row("subtitles", 2, 4)
mp.mouse(dx, dy)
mp.commands = {}
mp.button("press")
T.eq(last_cmd(), "set sid 1", "the first click chooses")
T.check(not menu().is_open(), "and closes the menu")
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "the double click is still swallowed where the menu was")
mp.commands = {}
mp.button("press")
T.eq(#mp.commands, 0, "the second click does nothing")
mp.mouse(dx + 3, dy + 2)
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "a small move right away keeps it")
mp.mouse(dx + 40, dy)
T.eq(mp.bindings["suji-bar-dbl"], nil, "moving away gives the mouse back to mpv")
-- With the cursor still, after mpv's double-click time (300 ms by default)
open("subtitles")
mp.mouse(dx, dy)
mp.button("press")
mp.advance(0.29)
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "still held within the double-click time")
T.eq(mp.props["input-builtin-dragging"], false, "and window dragging is off meanwhile")
mp.advance(0.02)
T.eq(suji_bindings(), "", "past it, with the cursor still: no binding left")
T.eq(mp.props["input-builtin-dragging"], true, "window dragging is back")
mp.advance(30)
T.eq(mp.active_timers(), 0, "and no timer left")
mp.props["input-doubleclick-time"] = 500
open("subtitles")
mp.mouse(dx, dy)
mp.button("press")
mp.advance(0.4)
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "it follows input-doubleclick-time")
mp.advance(0.11)
T.eq(suji_bindings(), "", "and ends with it")
-- Nonsense double-click times: the usual 300 ms
for _, bad in ipairs({ 0 / 0, -50, 1e9, "x" }) do
    mp.props["input-doubleclick-time"] = bad
    open("subtitles")
    mp.mouse(dx, dy)
    mp.button("press")
    mp.advance(0.29)
    local held = mp.bindings["suji-bar-dbl"] ~= nil
    mp.advance(0.02)
    T.check(held and suji_bindings() == "", "double-click time " .. tostring(bad) .. ": 300 ms")
end
mp.props["input-doubleclick-time"] = nil
-- The row changes, or a module fails, right after the click: the same
open("subtitles")
mp.mouse(dx, dy)
mp.button("press")
mp.set_opts({ controls = "pause,space,fullscreen" })
mp.advance(0.31)
T.eq(suji_bindings(), "", "controls changed after the click: no binding left")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timer")
mp.set_opts({ controls = "pause,time,space,subtitles,audio,playlist,more,volume,fullscreen" })
open("subtitles")
mp.mouse(dx, dy)
mp.button("press")
mod("subtitles").render = function() error("broken") end
mp.advance(0.31)
T.eq(suji_bindings(), "", "a module failed after the click: no binding left")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timer")
start({ ["track-list"] = SUBS })
open("subtitles")
click(row("subtitles", 2, 4))
mp.mouse(dx, dy, false)
mp.mouse(dx, dy)
T.eq(mp.bindings["suji-bar-dbl"], nil, "or leaving the window")

-- Opening another closes the first --------------------------------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
local closed = 0
local mc = mod("subtitles").menu_closed
mod("subtitles").menu_closed = function(...) closed = closed + 1; return mc(...) end
ctx_of("more").open_menu({ type = "x", items = items(3) }, box_of("more"))
T.check(menu().is_open(mod("more")), "the new one is open")
T.check(not menu().is_open(mod("subtitles")), "the old one is not")
T.eq(closed, 1, "its module heard it closed")
mp.advance(1)
T.check(shown(1) and not painted():find("}Off", 1, true), "only the new one is drawn")
mod("subtitles").menu_closed = mc
T.eq(ctx_of("more").open_menu({ type = "x", items = items(3) }, box_of("more")), false, "the same menu again closes it")
T.check(not menu().is_open(), "closed")

-- Placement: never out of the window ---------------------------------------------------------
start()
local far = { x0 = 1250, y0 = 658, x1 = 1270, y1 = 702 }
ctx_of("more").open_menu({ type = "x", items = items(3) }, far)
local y = Y1 - 15
T.check(menu().contains(1259, y), "moved left to fit")
T.check(not menu().contains(1260, y), "20 px from the right edge")
T.check(menu().contains(1080, y) and not menu().contains(1079, y), "180 px wide")
T.check(menu().contains(1100, Y1 + BG - 1) and not menu().contains(1100, Y1 + BG), "bottom 12 px above the row, panel 6 px more")
T.check(menu().contains(1100, Y1 - 90 - BG) and not menu().contains(1100, Y1 - 91 - BG), "three rows of 30 px")
menu().close(true)
ctx_of("more").open_menu({ type = "x", title = "A title", items = items(3) }, box_of("more"))
T.check(menu().contains(1050, Y1 - 116 - BG) and not menu().contains(1050, Y1 - 117 - BG), "a title adds 26 px on top")
T.check(painted() ~= "" and true, "drawn")
mp.advance(1)
T.check(painted():find("}A title", 1, true) ~= nil, "the title is shown")
T.check(painted():find("\\1c&H000000&\\1a&H66&\\p3}m [^{]* b ") ~= nil, "a black panel at 60% with round corners")
T.check(painted():find("\\1c&H000000&\\1a&H66&", 1, true) < painted():find("}A title", 1, true), "drawn behind the text")
T.check(painted():find("\\1a&H66&\\3a&H94&\\4a&HC2&}A title", 1, true) ~= nil, "dimmed")
menu().close(true)
start(nil, { scale = 2 })
ctx_of("more").open_menu({ type = "x", items = items(3) }, { x0 = 100, y0 = 600, x1 = 188, y1 = 688 })
T.check(menu().contains(100, 600 - 24 - 1) and not menu().contains(99, 575), "scale 2: aligned with the button")
T.check(menu().contains(459, 575) and not menu().contains(460, 575), "scale 2: 360 px wide")
T.check(menu().contains(100, 576 - 180 - 2 * BG) and not menu().contains(100, 576 - 181 - 2 * BG), "scale 2: rows of 60 px")

-- Height, the wheel and only what is on screen -------------------------------------------------
start()
ctx_of("more").open_menu({ type = "x", items = items(100) }, box_of("more"))
mp.advance(1)
T.check(menu().contains(1050, 646 - 600 - BG) and not menu().contains(1050, 645 - 600 - BG), "20 rows fit above the row")
T.check(shown(1) and shown(20) and not shown(21), "the first 20 are drawn")
T.check(painted():find("\\p3}m 4532 2586 l 4552 2606 l 4572 2586", 1, true) ~= nil, "a chevron says there is more below")
mp.mouse(row("more", 5, 100))
T.check(mp.bindings["suji-wheel-down"] ~= nil, "the wheel is bound over the menu")
mp.bindings["suji-wheel-down"].fn()
mp.advance(0.1)
T.check(not shown(2) and shown(3) and shown(22) and not shown(23), "the wheel scrolls two items")
T.check(painted():find("\\1a&HE6&", 1, true) ~= nil, "the item now under the cursor is highlighted")
mp.commands = {}
mp.button("press")
T.eq(last_cmd(), "show-text item 7", "and a click takes the item now under the cursor")
ctx_of("more").open_menu({ type = "x", items = items(100) }, box_of("more"))
for _ = 1, 100 do mp.bindings["suji-wheel-down"].fn() end
mp.advance(0.1)
T.check(shown(81) and shown(100) and not shown(80), "it stops at the end")
T.check(painted():find("m 4532 2586 l 4552 2606", 1, true) == nil, "no chevron below at the end")
T.check(painted():find("m 4532 178 l 4552 158", 1, true) ~= nil, "one above")
for _ = 1, 100 do mp.bindings["suji-wheel-up"].fn() end
mp.advance(0.1)
T.check(shown(1) and shown(20), "and at the start")
for _ = 1, 21 do mp.bindings["suji-menu-down"].fn() end -- the first shows the cursor on item 1
mp.advance(0.1)
T.check(not shown(1) and shown(2) and shown(21), "the keys scroll one item at a time")
mp.mouse(640, 300)
T.eq(mp.bindings["suji-wheel-down"], nil, "off the menu the wheel is mpv's")

start()
ctx_of("more").open_menu({ type = "x", items = items(10000) }, box_of("more"))
mp.advance(1)
T.eq(count(painted(), "}Item %d+"), 20, "10 000 items: 20 drawn")
T.check(#painted() < 20000, "a small paint")
T.check(shown(1) and not shown(21), "the first ones")

-- selected_index and the first active item ---------------------------------------------------------
start()
ctx_of("more").open_menu({ type = "x", items = items(1000), selected_index = 500 }, box_of("more"))
mp.advance(1)
T.check(shown(500), "selected_index is on screen")
ctx_of("more").open_menu({ type = "y", items = items(1000, function(i) return { active = i == 700 or i == 900 } end) },
    box_of("more"))
mp.advance(1)
T.check(shown(700), "without it, the first active one")
mp.bindings["suji-menu-enter"].fn()
T.eq(last_cmd(), "show-text item 700", "and Enter takes it")
ctx_of("more").open_menu({ type = "z", items = items(1000) }, box_of("more"))
mp.advance(1)
T.check(shown(1), "with no active one, the first")
ctx_of("more").open_menu({ type = "w", items = items(1000), selected_index = "nope" }, box_of("more"))
mp.advance(1)
T.check(shown(1), "a bad selected_index is ignored")
menu().close(true)

-- keep_open ------------------------------------------------------------------------------------------
start()
ctx_of("more").open_menu({ type = "x", keep_open = true, items = items(3) }, box_of("more"))
T.eq(click(row("more", 2, 3)), "show-text item 2", "keep_open on the menu: the item runs")
T.check(menu().is_open(), "and the menu stays")
menu().close(true)
ctx_of("more").open_menu({ type = "x", items = items(3, function(i) return { keep_open = i == 1 } end) }, box_of("more"))
click(row("more", 1, 3))
T.check(menu().is_open(), "keep_open on the item")
click(row("more", 2, 3))
T.check(not menu().is_open(), "another item closes it")

-- Headers and items that cannot be chosen -------------------------------------------------------------------
start()
ctx_of("more").open_menu({ type = "x", items = {
    { title = "Group", selectable = false, muted = true, italic = true },
    { title = "Choice", value = { "show-text", "c" }, bold = true, separator = true },
    { title = "Nope", value = { "show-text", "n" }, selectable = false },
} }, box_of("more"))
mp.advance(1)
T.check(painted():find("\\b0\\i1\\fsp0.0", 1, true) ~= nil, "italic")
T.check(painted():find("\\b1\\fsp0.0", 1, true) ~= nil, "bold")
T.check(painted():find("\\1a&H80&\\3a&HA6&\\4a&HCC&}Group", 1, true) ~= nil, "muted")
T.eq(click(row("more", 1, 3)), "", "a header does nothing")
T.check(menu().is_open(), "and keeps the menu")
T.eq(click(row("more", 3, 3)), "", "nor an item that cannot be chosen")
mp.mouse(row("more", 1, 3))
mp.advance(0.1)
T.check(painted():find("\\1a&HE6&", 1, true) == nil, "headers get no highlight")
T.eq(click(row("more", 2, 3)), "show-text c", "the other one runs")

-- A command that fails, and an action that fails, are logged ---------------------------------------
start()
local commandv = mp.commandv
mp.commandv = function(...) commandv(...); return nil, "error running command" end
ctx_of("more").open_menu({ type = "x", items = items(2) }, box_of("more"))
click(row("more", 1, 2))
T.eq(#logs("warn", "command failed"), 1, "a failed command is logged")
mp.commandv = commandv
ctx_of("more").open_menu({ type = "x", items = { { title = "Boom", action = function() error("boom") end },
                                               { title = "String", value = "show-text ok" } } }, box_of("more"))
click(row("more", 1, 2))
T.eq(#logs("error", "action failed"), 1, "a failed action is logged")
T.eq(open("subtitles"), "", "suji keeps working")
T.check(menu().is_open(mod("subtitles")), "a menu opens")
menu().close(true)
ctx_of("more").open_menu({ type = "x", items = { { title = "String", value = "show-text ok" } } }, box_of("more"))
mp.commands = {}
click(row("more", 1, 1))
T.eq(#mp.commands[1], 1, "a string value goes to mp.command")
T.eq(mp.commands[1][1], "show-text ok", "as it is")
-- Only suji's modules may give an action
local m = menu().clean({ type = "x", items = { { title = "f", action = function() end } } }, false)
T.eq(m.items[1].action, nil, "untrusted: no action")
T.eq(menu().clean({ type = "x", items = { { title = "f", action = function() end } } }, true).items[1].action ~= nil, true,
    "trusted: kept")
T.eq(menu().clean({ type = "x", items = { { value = { "a", 5 } } } }).items[1].value, nil, "a value with a number is dropped")
T.eq(menu().clean({ items = {} }).type, "", "a menu with no type has the type \"\"")
T.eq(menu().clean({ type = 5, items = {} }), nil, "a type that is not a string is refused")

-- safe: the module of an open menu fails ------------------------------------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
mod("subtitles").render = function() error("broken") end
mp.advance(1)
T.check(not menu().is_open(), "its menu closes")
mp.advance(1)
T.check(not painted():find("}Off", 1, true), "and goes")
T.eq(mp.live("track-list"), 1, "its live watch was stopped (one left: the audio button's)")
T.eq(click(42, 680), "cycle pause", "the rest keeps working")
open("more")
T.check(menu().is_open(mod("more")), "other menus open")

-- A new file: the menu is built again, or closes when its button goes -----------------------------------
start({ ["track-list"] = SUBS })
open("subtitles")
local next_file = { { type = "sub", id = 1, title = "New file" } }
mp.props["track-list"] = next_file
mp.fire("track-list", next_file)
mp.advance(0.1)
T.check(menu().is_open() and painted():find("}New file", 1, true) ~= nil, "the menu shows the new file's tracks")
mp.fire("idle-active", true)
T.check(not menu().is_open(), "idle with no file: the button goes and the menu closes")
mp.advance(1)
T.eq(box_of("subtitles"), nil, "no subtitles button")
T.eq(box_of("more"), nil, "no more button")
T.eq(suji_bindings():find("menu", 1, true), nil, "no keys left")

-- enabled=no closes it
start({ ["track-list"] = SUBS })
open("subtitles")
mp.set_opts({ enabled = false })
T.check(not menu().is_open(), "disabled: closed")
T.eq(suji_bindings(), "", "no bindings")

-- Audio --------------------------------------------------------------------------------------------------
start({ ["track-list"] = SUBS })
T.eq(box_of("audio"), nil, "one track: no audio button")
local two = { SUBS[1], SUBS[2], { type = "audio", id = 2, title = "Commentary", lang = "eng" },
              { type = "audio", id = 3, title = "Speakers \27[31m{\\pos(0,0)}\n" .. ("\226\128\174"):rep(3) } }
mp.props["track-list"] = two
mp.fire("track-list", two)
T.check(box_of("audio") ~= nil, "more than one track: shown at once")
open("audio")
p = painted()
T.check(p:find("}jpn", 1, true) and p:find("}Commentary", 1, true), "the tracks")
T.check(not p:find("}Devices", 1, true) and not p:find("}Auto", 1, true), "no devices")
T.check(not p:find("\27", 1, true) and not p:find("{\\pos(0,0)}", 1, true), "a strange title is made harmless")
T.check(p:find("}Speakers ?[31m\\{\\\226\128\139pos(0,0)\\}?", 1, true) ~= nil, "control characters and braces shown as text")
T.eq(#marks(p), 1, "the active track is marked")
T.eq(click(row("audio", 2, 3)), "set aid 2", "a track")
T.eq(mp.observed["audio-device-list"], nil, "the devices are not watched")
mp.fire("track-list", SUBS)
T.eq(box_of("audio"), nil, "back to one track: hidden")

-- Playlist and chapters ------------------------------------------------------------------------------------
local CHAPTERS = { { time = 0, title = "Opening" }, { time = 20 }, { time = 70.5, title = "End" } }
start({ chapters = 3 })
T.check(box_of("playlist") ~= nil, "chapters: shown")
mp.props["chapter-list"], mp.props.chapter = CHAPTERS, 1
mp.props.playlist = { { filename = "a.mkv", current = true } }
open("playlist")
p = painted()
T.check(p:find("}Opening", 1, true) and p:find("}Chapter 2", 1, true) and p:find("}End", 1, true), "titles, or Chapter N")
T.check(not p:find("}Chapters", 1, true) and not p:find("}a.mkv", 1, true), "only chapters: no headers, no playlist")
T.check(p:find("}01:10", 1, true) ~= nil, "the start in the hint, as in the row")
T.eq(marks(p)[1], Y1 - 90 + 45 - 7, "the current chapter is marked")
T.eq(click(row("playlist", 3, 3)), "set chapter 2", "the third chapter")
mp.fire("chapters", 0)
T.eq(box_of("playlist"), nil, "no chapters, one entry: hidden")
set_playlist({ { filename = "/a/b/One.mkv" }, { filename = "C:\\videos\\Two.mkv", title = "" },
               { filename = "https://example.com/watch/Three.mp4?t=10&x=1#frag", current = true },
               { filename = "https://example.com?x=1" }, { filename = "x.mp3", title = "Titled" } })
T.check(box_of("playlist") ~= nil, "five entries: shown")
open("playlist")
p = painted()
T.check(p:find("}One.mkv", 1, true) and p:find("}Two.mkv", 1, true) and p:find("}Three.mp4", 1, true), "the last part of a path")
T.check(p:find("}https://example.com\n", 1, true) or p:find("}https://example.com$"), "a URL with no path, without its query")
T.check(p:find("}Titled", 1, true) ~= nil and not p:find("t=10", 1, true), "a title first; never the query")
T.eq(click(row("playlist", 2, 5)), "playlist-play-index 1", "an entry")
mp.props["chapter-list"], mp.props.chapter = CHAPTERS, 0
mp.fire("chapters", 3)
open("playlist")
p = painted()
T.check(p:find("}Chapters", 1, true) and p:find("}Playlist", 1, true), "both: two headers")
T.eq(click(row("playlist", 7, 10)), "playlist-play-index 1", "chapters, header, then the playlist")
T.eq(menu().is_open(), false, "closed")
open("playlist")
T.eq(click(row("playlist", 4, 10)), "set chapter 2", "the chapters on top")
T.eq(mod("playlist").file_name(("a/"):rep(300000) .. "end.mkv"), "end.mkv", "a huge path is cheap")
T.eq(mod("playlist").file_name("https://h/" .. ("x"):rep(100) .. "?" .. ("q"):rep(1000000)), ("x"):rep(100), "a huge query")

-- Playlist: only what can be played. mpv puts every entry of a folder in it, subfolders too.
local MIXED = { { filename = "C:\\Users\\u\\AppData" }, { filename = "C:\\Users\\u\\a.mkv" }, { filename = "/home/u/Desktop" },
                { filename = "/home/u/B.MKV" }, { filename = "/home/u/song.flac" }, { filename = "/home/u/README" },
                { filename = "https://example.com/live" } }
start({ playlist = MIXED })
T.check(box_of("playlist") ~= nil, "four entries to list: shown")
open("playlist")
p = painted()
T.check(p:find("}a.mkv", 1, true) and p:find("}B.MKV", 1, true) and p:find("}song.flac", 1, true) and p:find("}live", 1, true),
    "video, audio in any case, and the URL")
T.check(not p:find("}AppData", 1, true) and not p:find("}Desktop", 1, true), "no folders")
T.check(not p:find("}README", 1, true), "no file without an extension")
T.eq(click(row("playlist", 2, 4)), "playlist-play-index 3", "mpv's index of the entry, not its row")
open("playlist")
T.eq(click(row("playlist", 4, 4)), "playlist-play-index 6", "the URL, the last one")

local FOLDERS = { { filename = "/home/u/a.mkv", current = true }, { filename = "/home/u/Desktop" }, { filename = "/home/u/Music" } }
start({ playlist = FOLDERS, chapters = 3 })
mp.props["chapter-list"], mp.props.chapter = CHAPTERS, 0
open("playlist")
p = painted()
T.check(not p:find("}Chapters", 1, true) and not p:find("}Playlist", 1, true), "one entry to list: no headers")
T.check(not p:find("}a.mkv", 1, true) and not p:find("}Desktop", 1, true), "and only the chapters")
menu().close(true)
mp.fire("chapters", 0)
T.eq(box_of("playlist"), nil, "no chapters and one entry to list: no button, with three in the playlist")
local two_files = { FOLDERS[1], FOLDERS[2], { filename = "/home/u/b.mp4" } }
set_playlist(two_files)
T.check(box_of("playlist") ~= nil, "a second file: shown at once")
set_playlist(FOLDERS)
T.eq(box_of("playlist"), nil, "only folders again: hidden")

local ON_FOLDER = { { filename = "/home/u/Desktop", current = true }, { filename = "/home/u/a.mkv" }, { filename = "/home/u/Music" } }
start({ playlist = ON_FOLDER })
T.check(box_of("playlist") ~= nil, "the current entry and a file: shown")
open("playlist")
p = painted()
T.check(p:find("}Desktop", 1, true) and p:find("}a.mkv", 1, true), "the current entry is listed, even a folder")
T.check(not p:find("}Music", 1, true), "the other folders are not")
T.eq(#marks(p), 1, "and it is marked")
T.eq(click(row("playlist", 2, 2)), "playlist-play-index 1", "the file after it")

local deep = {}
for i = 1, 999 do deep[i] = { filename = "/home/u/folder " .. i } end
deep[1000], deep[1001] = { filename = "/home/u/a.mkv" }, { filename = "/home/u/b.mkv" }
start({ playlist = deep })
T.eq(box_of("playlist"), nil, "files past the first 1000 entries are not counted")
deep[999] = { filename = "/home/u/c.mkv" }
set_playlist(deep)
T.check(box_of("playlist") ~= nil, "the 999th and the 1000th are")
open("playlist")
T.eq(count(painted(), "}[abc]%.mkv"), 3, "the menu lists the three: it is not bound by the count")

-- The extensions: mpv's lists when it has them (0.40), as the user set them
local EXTS = { { filename = "/m/a.mkv" }, { filename = "/m/b.MKV" }, { filename = "/m/c.xyz" }, { filename = "/m/d.cbz" } }
start({ playlist = EXTS })
T.eq(box_of("playlist") ~= nil, true, "no video-exts (mpv 0.39): suji's own list, a.mkv and b.MKV")
open("playlist")
T.check(not painted():find("}c.xyz", 1, true) and not painted():find("}d.cbz", 1, true), "and nothing else")
start({ playlist = EXTS, ["video-exts"] = { "XYZ" }, ["audio-exts"] = {} })
T.eq(box_of("playlist"), nil, "video-exts=xyz: only c.xyz, one entry")
local reads_exts = 0
local get_number = mp.get_property_number
mp.get_property_number = function(name, def)
    if name == "playlist-count" then reads_exts = reads_exts + 1 end
    return get_number(name, def)
end
mp.props["audio-exts"] = { "cbz" }
mp.fire("audio-exts", { "cbz" })
mp.advance(0)
T.check(box_of("playlist") ~= nil, "audio-exts changed: c.xyz and d.cbz")
T.eq(reads_exts, 1, "and counted again")
open("playlist")
p = painted()
T.check(p:find("}c.xyz", 1, true) and p:find("}d.cbz", 1, true) and not p:find("}a.mkv", 1, true), "the menu follows them")
menu().close(true)
mp.fire("video-exts", nil)
mp.fire("audio-exts", nil)
mp.advance(0)
open("playlist")
T.check(painted():find("}a.mkv", 1, true) ~= nil, "back to suji's list when mpv has none")

-- Several changes of the playlist for one new file: one count
start({ playlist = MIXED })
local counted = 0
get_number = mp.get_property_number
mp.get_property_number = function(name, def)
    if name == "playlist-count" then counted = counted + 1 end
    return get_number(name, def)
end
for _ = 1, 4 do mp.fire("playlist") end
T.eq(counted, 0, "not counted on each change")
mp.advance(0)
T.eq(counted, 1, "but once after them")
mp.advance(5)
T.eq(mp.active_timers(), 0, "and no timer left")

-- Playlist: 30 000 entries, opened on the current one, and an update keeps the scroll
local big = {}
for i = 1, 30000 do big[i] = { filename = ("/v/Episode %d.mkv"):format(i), current = i == 25000 } end
start({ playlist = big })
local reads = 0
local get_native = mp.get_property_native
mp.get_property_native = function(name, def)
    if name == "playlist" then reads = reads + 1 end
    return get_native(name, def)
end
local t0 = os.clock()
open("playlist")
local took = os.clock() - t0
mp.advance(1)
T.eq(reads, 1, "opening reads the playlist once, also after mpv sends the first values")
T.check(painted():find("}Episode 25000.mkv", 1, true) ~= nil, "30 000 entries: opened on the current one")
T.eq(count(painted(), "}Episode %d+"), 20, "20 drawn")
T.check(took < 2, ("opened in %.2f s"):format(took))
mp.mouse(row("playlist", 5, 20))
mp.bindings["suji-wheel-down"].fn()
mp.advance(0.1)
local before_scroll = painted():match("}(Episode %d+)%.mkv")
big[25000].current, big[25001] = false, { filename = "/v/Renamed.mkv", current = true }
mp.fire("playlist", big)
mp.advance(0.1)
T.eq(painted():match("}(Episode %d+)%.mkv"), before_scroll, "an update keeps the scroll")
T.check(painted():find("}Renamed.mkv", 1, true) ~= nil, "with the new data")
T.eq(mp.live("playlist"), 1, "the playlist is watched while open")
menu().close(true)
T.eq(mp.live("playlist"), 1, "and after, with no value, for the button")

-- Chapters and 30 000 entries: a new chapter moves the mark, nothing more
start({ playlist = big, chapters = 3 })
mp.props.playlist, mp.props["chapter-list"], mp.props.chapter = big, { { time = 0 }, { time = 30 }, { time = 60 } }, 0
reads = 0
get_native = mp.get_property_native
mp.get_property_native = function(name, def)
    if name == "playlist" then reads = reads + 1 end
    return get_native(name, def)
end
big[25000].current = false
big[1].current = true
open("playlist") -- Chapters, three chapters, Playlist, then the entries
T.eq(reads, 1, "one read to open")
T.eq(marks()[1], Y1 - 20 * 30 + 45 - 7, "chapter 1 is marked (item 2)")
t0 = os.clock()
mp.props.chapter = 2
mp.fire("chapter", 2)
mp.advance(0.1)
T.eq(reads, 1, "a new chapter does not read the playlist again")
T.check(os.clock() - t0 < 0.1, ("and costs little (%.3f s)"):format(os.clock() - t0))
T.eq(marks()[1], Y1 - 20 * 30 + 105 - 7, "the mark moved to chapter 3 (item 4)")
T.eq(#marks(), 2, "and the current entry keeps its own")
mp.props.chapter = -1
mp.fire("chapter", -1)
mp.advance(0.1)
T.eq(#marks(), 1, "before the first chapter: no chapter marked")

-- More --------------------------------------------------------------------------------------------------------
start({ ["property-list"] = { "pause", "clipboard" } })
mp.props["track-list"] = { { type = "video", id = 1, title = "Main", selected = true }, { type = "video", id = 2, lang = "und" },
                           { type = "audio", id = 1 } }
mp.props["edition-list"] = { { id = 0, title = "Cut" }, { id = 1 } }
mp.props["current-edition"] = 1
open("more")
p = painted()
T.check(p:find("}Video", 1, true) and p:find("}Main", 1, true) and p:find("}und", 1, true), "video tracks with a header")
T.check(p:find("}Editions", 1, true) and p:find("}Cut", 1, true) and p:find("}Edition 2", 1, true), "editions")
T.eq(count(p, "}restarts"), 2, "an edition says it restarts")
T.check(not p:find("}Speed", 1, true) and not p:find("\195\151", 1, true), "no speeds: they have their own button")
T.check(p:find("}Open from clipboard", 1, true) ~= nil, "mpv 0.40: open from the clipboard")
T.eq(#marks(p), 2, "video and edition marked")
-- Video, Main, und, Editions, Cut, Edition 2, Open: 7 rows
T.eq(click(row("more", 3, 7)), "set vid 2", "a video track")
open("more")
T.eq(click(row("more", 5, 7)), "set edition 0", "an edition")
mp.props["edition-list"] = { { id = 0 } }
mp.props["track-list"] = { { type = "video", id = 1 } }
menu().close(true)
open("more")
p = painted()
T.check(not p:find("}Video", 1, true) and not p:find("}Editions", 1, true), "one video track and one edition: not listed")

-- More hides when it has nothing to offer: no clipboard (mpv 0.39), one video track, no editions
start({ ["edition-list"] = false, ["track-list"] = { { type = "video", id = 1 } } })
T.eq(box_of("more"), nil, "nothing to offer: no more button")
T.check(box_of("speed") ~= nil, "the speed button is there")
local two = { { type = "video", id = 1 }, { type = "video", id = 2 } }
mp.props["track-list"] = two
mp.fire("track-list", two)
T.check(box_of("more") ~= nil, "a second video track: more appears")
mp.fire("edition-list/count", 2)
mp.fire("track-list", { { type = "video", id = 1 } })
T.check(box_of("more") ~= nil, "two editions: it stays")
mp.fire("edition-list/count", 0)
T.eq(box_of("more"), nil, "neither: it goes")

-- Speed ---------------------------------------------------------------------------------------------------
start({ speed = 1.5 })
mp.fire("speed", 1.5)
open("speed")
p = painted()
T.check(p:find("}Speed{", 1, true) == nil and p:find("}Speed", 1, true) ~= nil, "the title")
T.check(p:find("}0.25\195\151", 1, true) and p:find("}1.75\195\151", 1, true) and p:find("}4\195\151", 1, true),
    "0.25x to 4x")
T.eq(#marks(p), 1, "one marked")
T.eq(marks(p)[1], Y1 - 10 * 30 + 165 - 7, "1.5x, the sixth")
T.eq(click(row("speed", 8, 10)), "set speed 2", "2x")
T.eq(click(row("speed", 1, 10)), "", "the menu closed after the choice: nothing there now")
mp.props.speed = 1.0004
open("speed")
T.eq(marks()[1], Y1 - 10 * 30 + 105 - 7, "1.0004: 1x marked")
menu().close(true)
mp.props.speed = 1.2345
open("speed")
p = painted()
T.eq(#marks(p), 0, "1.2345: none marked")
T.check(p:find("}Speed  1.23\195\151", 1, true) ~= nil, "the title says which")
menu().close(true)
mp.advance(1)
-- The speed in the corner of the button
local function corner()
    return painted():match("}([%d.]+)\195\151")
end
for _, c in ipairs({ { 1, nil }, { 1.5, "1.5" }, { 0.75, "0.75" }, { 2, "2" }, { 1.2345, "1.23" }, { 0.01, "0.01" },
                     { 100, "100" }, { 33.333, "33.3" } }) do
    mp.fire("speed", c[1])
    mp.advance(1)
    T.eq(corner(), c[2], "the button at " .. c[1])
end
local timers = mp.active_timers()
mp.fire("speed", 33.3301)
T.eq(mp.active_timers(), timers, "a change that looks the same: no paint")
T.eq(box_of("speed").x1 - box_of("speed").x0, 44, "the width does not change")

-- The clipboard: one argument, as it is ---------------------------------------------------------------------
start({ ["property-list"] = { "pause", "clipboard" }, ["edition-list"] = false, ["track-list"] = { { type = "video", id = 1 } } })
mp.props["clipboard/text"] = "  /tmp/a b; quit ${path} `x` \"q\"\nsecond line; quit\r\n"
local items_n = 1 -- only Open
open("more")
T.eq(click(row("more", 1, items_n)), "loadfile /tmp/a b; quit ${path} `x` \"q\" replace", "open from the clipboard")
local c = mp.commands[#mp.commands]
T.eq(#c, 3, "through mp.commandv")
T.eq(c[2], "/tmp/a b; quit ${path} `x` \"q\"", "the first line, trimmed, as one argument")
mp.props["clipboard/text"] = (" "):rep(100000) .. "x"
open("more")
T.eq(click(row("more", 1, items_n)), "show-text Clipboard is empty 1500", "only the first 4 KiB are read")
mp.props["clipboard/text"] = nil
open("more")
T.eq(click(row("more", 1, items_n)), "show-text Clipboard is empty 1500", "an empty clipboard says so")
start({ ["property-list"] = { "pause", "clipboard" }, ["track-list"] = {} })
mp.props["clipboard/text"] = "https://example.com/s.srt\n;quit"
open("subtitles")
T.eq(click(row("subtitles", 2, 2)), "sub-add https://example.com/s.srt", "load subtitles from the clipboard")
T.eq(#mp.commands[#mp.commands], 2, "one argument")
-- Only a local path, file:// and http(s)://: other protocols could do much
-- more than play a file (av://lavfi can write files).
local refused = { "av://lavfi:sine,metadata=mode=print:file=/home/u/.bashrc", "AV://lavfi:x", "Av://x",
                  "lavf://x", "fd://3", "fdclose://3", "edl://a.mkv,0,1", "memory://x", "ytdl://x",
                  "  av://x", "mf://*.png", "x-y.z+w://a" }
for _, text in ipairs(refused) do
    mp.props["clipboard/text"] = text
    open("subtitles")
    T.eq(click(row("subtitles", 2, 2)), "show-text Clipboard: unsupported address 1500", "refused: " .. text)
end
local allowed = { ["C:\\Videos\\subs.ass"] = "C:\\Videos\\subs.ass", ["C:/Videos/subs.ass"] = "C:/Videos/subs.ass",
                  ["/home/u/subs.ass"] = "/home/u/subs.ass", ["file:///home/u/a.srt"] = "file:///home/u/a.srt",
                  ["FILE:///x.srt"] = "FILE:///x.srt", ["https://example.com/a.srt"] = "https://example.com/a.srt",
                  ["HTTP://example.com/a.srt"] = "HTTP://example.com/a.srt", ["subs/a:b.srt"] = "subs/a:b.srt" }
for text, arg in pairs(allowed) do
    mp.props["clipboard/text"] = text
    open("subtitles")
    T.eq(click(row("subtitles", 2, 2)), "sub-add " .. arg, "allowed: " .. text)
end
mp.props["clipboard/text"] = "av://lavfi:x"
open("more")
T.eq(click(row("more", 12, 12)), "show-text Clipboard: unsupported address 1500", "open from the clipboard refuses it too")
start()
open("subtitles")
T.check(not painted():find("clipboard", 1, true), "mpv 0.39 (no clipboard property): no clipboard entries")
open("more")
T.check(not painted():find("clipboard", 1, true), "in more neither")

-- Hostile text ---------------------------------------------------------------------------------------------------
local huge = ("\226\150\136"):rep(400000) -- 1.2 MB
start({ ["track-list"] = { { type = "sub", id = 1, title = huge, lang = huge },
                           { type = "sub", id = 2, title = "a\0b\7c\27[2J{\\fs200}\\N\226\128\174d" } } })
t0 = os.clock()
open("subtitles")
T.check(os.clock() - t0 < 1, "1 MB titles open fast")
p = painted()
T.check(#p < 20000, "and paint little")
T.check(not p:find("[%z\1-\9\11-\31]"), "no control characters reach the ASS")
T.check(not p:find("{\\fs200}", 1, true) and p:find("\\{\\\226\128\139fs200\\}", 1, true), "an ASS tag in a title is text")
T.check(not p:find("\\N", 1, true), "and so is \\N")
local big_ch = {}
for i = 1, 30000 do big_ch[i] = { time = i / 300, title = huge } end
start({ chapters = 30000 })
mp.props["chapter-list"] = big_ch
t0 = os.clock()
open("playlist")
T.check(os.clock() - t0 < 5, "30 000 chapters with 1 MB titles open")
T.check(#painted() < 30000, "and paint little")
T.check(package.loaded["core.modules"].alive(mod("playlist")), "the module is alive")

-- The menu buttons in the controls option, with conditions -------------------------------------------
start({ ["track-list"] = SUBS }, { controls = "more,<user-data/x>subtitles,space,fullscreen" })
T.eq(box_of("more").x0, 20, "more first")
T.eq(box_of("subtitles"), nil, "a condition hides subtitles")
mp.fire("user-data/x", "yes")
T.eq(box_of("subtitles").x0, 72, "and shows it")
T.eq(box_of("volume"), nil, "only what is listed")
open("subtitles")
mp.set_opts({ controls = "pause,space,fullscreen" })
T.check(not menu().is_open(), "its button left the row: the menu closes")

-- Only one observer per property, and none of the live ones at rest ---------------------------------------
local fake_mp = T.fake_mp
local kinds -- kind of each observer, by property
T.fake_mp = function(...)
    local m = fake_mp(...)
    local observe = m.observe_property
    kinds = {}
    m.observe_property = function(name, kind, fn)
        kinds[name] = (kinds[name] and kinds[name] .. " " or "") .. kind
        return observe(name, kind, fn)
    end
    return m
end
start({ ["track-list"] = SUBS, playlist = MIXED })
T.fake_mp = fake_mp
for prop, n in pairs(mp.observed) do T.eq(n, 1, "one observer for " .. prop) end
T.eq(kinds.playlist, "none", "the playlist at rest: watched with no value")
local native_reads = 0
get_native = mp.get_property_native
mp.get_property_native = function(name, def)
    if name == "playlist" then native_reads = native_reads + 1 end
    return get_native(name, def)
end
set_playlist(FOLDERS)
set_playlist(MIXED)
T.eq(native_reads, 0, "and never read whole while the menu is closed")
T.eq(mp.live("chapter-list"), 1, "chapter-list: the timeline's only")
T.eq(mp.live("speed"), 1, "the speed: only the speed button's, for its corner")

T.done("test_menu")
