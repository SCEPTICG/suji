-- The modules through main.lua and a fake mp: shared observers, safe calls,
-- the controls option changed at run time and its conditions.
local T = require "lib"

local function start(script_opts, props)
    T.unload()
    props = props or {}
    props["mpv-version"] = props["mpv-version"] or "mpv v0.40.0"
    mp = T.fake_mp(props)
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = 1280, h = 720 })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", true)
    mp.fire("time-pos", 50)
    mp.fire("volume", 100)
    mp.mouse(0, 0)
    mp.advance(1)
    return mp
end
local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function last_cmd() local c = mp.commands[#mp.commands]; return c and table.concat(c, " ") end
local function logs(level, pattern)
    local t = {}
    for _, l in ipairs(mp.logs) do
        if l[1] == level and (not pattern or tostring(l[2]):find(pattern, 1, true)) then t[#t + 1] = l[2] end
    end
    return t
end
local function click(x, y) mp.mouse(x, y); mp.commands = {}; mp.button("press"); return last_cmd() end
local mods = function() return package.loaded["core.modules"] end
local function mouse() return package.loaded["core.mouse"] end

-- revive: a module that watches and unwatches while it gets its values
-- back. Each delivery drops its own watch (its key leaves the table of
-- watches) and adds many (the table grows): walking that table live would
-- break, or skip and repeat.
start()
do
    local m = { render = function() error("off") end }
    local ctx = mods().ctx_of(m)
    local reviving, got, extra = false, 0, 0
    local handles = {}
    for i = 1, 20 do
        local name = "user-data/r" .. i
        handles[i] = ctx.watch(name, "native", function()
            if not reviving then return end
            got = got + 1
            ctx.unwatch(handles[i])
            for k = 1, 40 do ctx.watch(("user-data/n%d_%d"):format(i, k), "native", function() extra = extra + 1 end) end
        end)
        mp.fire(name, i)
    end
    mods().call(m, "render")
    T.check(not mods().alive(m), "the module failed")
    reviving = true
    local ok, err = pcall(mods().revive, m)
    T.check(ok, "revive with watches changing on the way: no error (" .. tostring(err) .. ")")
    T.eq(got, 20, "each watch got its value once")
    T.eq(extra, 0, "the new ones, of properties never seen, get nothing yet")
    T.eq(mods().alive(m), true, "revived")
end

-- Shared observers: one per property, however many ask -------------------
start()
for prop, n in pairs(mp.observed) do T.eq(n, 1, "one observer for " .. prop) end
T.check(mp.observed["time-pos"] == 1 and mp.observed["duration"] == 1, "time-pos and duration are shared")
local seen = {}
mods().watch("volume", "number", function(v) seen[#seen + 1] = v end)
T.eq(mp.observed.volume, 1, "a new watcher of the same property adds no observer")
T.eq(seen[1], 100, "and gets the value seen so far at once")
mp.fire("volume", 30)
T.eq(seen[2], 30, "then each change")
mods().watch("volume", "native", function() end)
T.eq(mp.observed.volume, 2, "another type is another observer")

-- watch: a repaint only when the controls are on screen
start({ idle_line = false })
mp.fire("pause", false)
mp.mouse(640, 100)
mp.advance(5)
local n = #mp.updates
mp.fire("fullscreen", true)
mp.fire("volume", 20)
mp.advance(1)
T.eq(#mp.updates, n, "hidden: module watchers do not repaint")
T.eq(mp.active_timers(), 0, "hidden: no timers")
mp.fire("pause", true)
mp.advance(1)
n = #mp.updates
mp.fire("fullscreen", false)
mp.advance(0.1)
T.eq(#mp.updates, n + 1, "shown: a module watcher repaints")

-- safe: a module that fails in render is turned off -----------------------
start({ controls = "pause,time,space,volume,fullscreen" }) -- nothing slides into its place
local volume = package.loaded["modules.volume"]
mp.mouse(1186, 680) -- on the speaker: the slider unfolds, the volume grows leftwards
mp.advance(0.3)
mp.mouse(1170, 680)
mp.button("down")
T.check(mouse().captured() == volume, "the slider holds the mouse")
T.check(painted():find("m 4435 2709", 1, true) ~= nil, "the speaker is drawn")
volume.render = function() error("broken \27[31m render") end
mp.advance(1)
T.eq(mouse().captured(), nil, "a failed module lets go of the mouse")
local errs = logs("error", "volume")
T.eq(#errs, 1, "the failure is logged")
T.check(errs[1] and not errs[1]:find("[%z\1-\31\127]"), "the log has no control characters")
T.check(errs[1] and errs[1]:find("render", 1, true) ~= nil, "it says where it failed")
T.check(painted():find("m 4435 2709", 1, true) == nil, "not drawn any more")
T.check(painted():find("}00:50{", 1, true) ~= nil, "the rest is drawn")
mp.button("up")
mp.mouse(1180, 680)
mp.fire("time-pos", 51)
mp.advance(1)
T.eq(#logs("error", "volume"), 1, "logged once")
T.eq(mp.bindings["suji-bar"], nil, "its zone takes no clicks")
T.eq(mp.bindings["suji-wheel-up"], nil, "nor the wheel")
T.eq(click(1240, 680), "cycle fullscreen", "the others keep working")
T.eq(click(42, 680), "cycle pause", "the left part keeps working")

-- safe: a module that fails in press, and one that returns nonsense
start()
package.loaded["modules.pause"].press = function() error("no") end
mp.mouse(42, 680)
mp.button("down")
T.eq(mouse().captured(), nil, "a failed press holds nothing")
T.eq(#logs("error", "pause"), 1, "logged")
mp.button("up")
mp.mouse(43, 680)
local tb = package.loaded["core.layout"].find(package.loaded["core.layout"].current(), package.loaded["modules.time"])
T.eq(package.loaded["core.layout"].find(package.loaded["core.layout"].current(), package.loaded["modules.volume"]).x0,
    20, "turned off: no gap, the volume takes its place")
T.eq(tb.x0, 72, "and the time follows")
package.loaded["modules.fullscreen"].width = function() return 0 / 0 end
mp.mouse(44, 680)
mp.advance(1)
T.check(painted():find("4923 2709", 1, true) == nil, "a NaN width turns it off")
T.eq(#logs("error", "fullscreen"), 1, "and is logged")
start()
package.loaded["modules.time"].render = function() return {} end
mp.mouse(640, 690)
mp.advance(1)
T.eq(#logs("error", "time"), 1, "render must return a string")
T.check(painted() ~= "", "and suji keeps drawing")
start()
package.loaded["modules.fullscreen"].render = function() return ("x"):rep(70000) end
mp.mouse(640, 690)
mp.advance(1)
T.eq(#logs("error", "fullscreen"), 1, "render may not return megabytes")

-- safe: a watcher of a module that fails turns the module off
T.unload()
mp = T.fake_mp({ ["mpv-version"] = "mpv v0.40.0" })
package.loaded["modules.fullscreen"] = { init = function(ctx) ctx.watch("fullscreen", "bool", function() error("bad") end) end,
                                         width = function() return 44 end, render = function() return "" end }
dofile("suji/main.lua")
mp.fire("osd-dimensions", { w = 1280, h = 720 })
mp.fire("fullscreen", true)
T.eq(#logs("error", "watch fullscreen"), 1, "a failing watcher is logged")
T.check(not mods().alive(package.loaded["modules.fullscreen"]), "and its module is turned off")
mp.fire("fullscreen", false)
T.eq(#logs("error", "fullscreen"), 1, "once")

-- The controls option changed at run time ---------------------------------
start({ debug = true })
mp.set_opts({ controls = "fullscreen,space,pause" })
mp.advance(1)
T.eq(click(42, 680), "cycle fullscreen", "reordered at once: fullscreen on the left")
T.eq(click(1240, 680), "cycle pause", "and pause on the right")
T.eq(click(100, 680), nil, "the time is gone")
T.eq(click(1176, 680), nil, "and the volume")
T.check(not painted():find("} / 01:40", 1, true), "not drawn")
T.check(painted():find("\\an7\\pos(32.0,24.0)", 1, true) ~= nil, "the title is still there")
mp.set_opts({ controls = "pause,nope,command:x:set pause yes,space,volume,fullscreen" })
mp.advance(1)
T.eq(#logs("warn", "'nope'"), 1, "an unknown element is warned")
T.eq(click(42, 680), "cycle pause", "pause back")
T.eq(click(80, 680), "set pause yes", "a command button after it")
mp.set_opts({ controls = "pause,nope,space,volume" })
mp.set_opts({ controls = "pause,nope,command:x:set pause yes,space,volume,fullscreen" })
T.eq(#logs("warn", "'nope'"), 1, "warned only once")
mp.set_opts({ controls = "pause,pause,space,fullscreen" })
mp.advance(1)
T.eq(#logs("warn", "listed twice"), 1, "a module listed twice is warned")
T.eq(click(80, 680), nil, "and shown once")
mp.set_opts({ controls = "" })
mp.advance(1)
T.eq(click(42, 680), nil, "an empty row")
T.check(painted():find("\\an7\\pos(32.0,24.0)", 1, true) ~= nil, "still the title and the timeline")
T.check((click(42, 645) or ""):find("^seek") ~= nil, "the timeline is always there")
mp.set_opts({ controls = "pause,time,space,volume,fullscreen" })

-- A drag ends when its module leaves the row
start()
mp.mouse(94, 680) -- on the speaker: the slider unfolds from 116 to 180
mp.advance(0.3)
mp.mouse(148, 680)
mp.button("down")
T.check(mouse().captured() == package.loaded["modules.volume"], "the slider holds the mouse")
mp.set_opts({ controls = "pause,time" })
T.eq(mouse().captured(), nil, "the module left the row: it lets go")
mp.commands = {}
mp.mouse(50, 680)
T.eq(#mp.commands, 0, "no volume change")
mp.button("up")
start()
mp.mouse(640, 645)
mp.button("down")
mp.set_opts({ controls = "pause" })
T.check(package.loaded["modules.timeline"].dragging(), "the timeline is not part of the row: it keeps its drag")
mp.button("up")

-- Conditions ------------------------------------------------------------------
start({ controls = "pause,<has_playlist>command:x:playlist-next,<!user-data/demo/off>time,space,volume" })
T.eq(mp.observed["playlist-count"], 1, "a condition watches its property")
T.eq(mp.observed["user-data/demo/off"], 1, "user-data too")
local st = package.loaded["core.state"]
T.eq(click(80, 680), nil, "no playlist: the button leaves no gap")
T.eq(st.remaining, true, "the time is there and took the click")
mp.fire("playlist-count", 3)
T.eq(click(80, 680), "playlist-next", "playlist: the button appears at once")
mp.fire("user-data/demo/off", "yes")
mp.fire("playlist-count", 1)
mp.advance(1)
T.check(not painted():find("} / -00:50", 1, true), "the time is hidden by user-data")
T.eq(click(80, 680), nil, "and nothing is there")
local placed = 0
local layout = package.loaded["core.layout"]
local cur = layout.current
layout.current = function() placed = placed + 1; return cur() end
mp.fire("playlist-count", 1)
mp.fire("user-data/demo/off", "yes")
T.eq(placed, 0, "a change that does not change the row lays out nothing")
mp.fire("playlist-count", 5)
T.check(placed > 0, "a change that does, lays out again")
layout.current = cur

-- A condition on a property a module already watches shares the observer
start({ controls = "<fullscreen>pause,time" })
T.eq(mp.observed["fullscreen"], 2, "bool for the module, native for the condition")
mp.fire("fullscreen", true)
T.eq(click(42, 680), "cycle pause", "the condition sees the value")

-- Limits on the number of watched properties: one warning per reading
local list = {}
for i = 1, 70 do list[i] = "<user-data/p" .. i .. ">pause" end
start({ controls = table.concat(list, ",") })
T.eq(#logs("warn", "properties in conditions"), 0, "32 elements at most, so not over the limit here")
local cond = {}
for i = 1, 500 do cond[i] = "a" .. i end
start({ controls = "<" .. table.concat(cond, ",") .. ">pause" })
local over = logs("warn", "properties in conditions")
T.eq(#over, 1, "more than 64 properties: a single warning")
T.check(over[1] and over[1]:find("436 properties", 1, true) ~= nil, "saying how many are ignored")
T.eq(mp.observed.a64, 1, "the first 64 are watched")
T.eq(mp.observed.a65, nil, "the rest are not")
mp.fire("a65", true)
T.eq(click(42, 680), nil, "an ignored property counts as false")
mp.fire("a64", true)
T.eq(click(42, 680), "cycle pause", "a watched one works")

-- Old conditions are not watched any more: 200 reloads, a new property each
start()
for i = 1, 200 do
    mp.set_opts({ controls = ("<user-data/r%d>pause,time"):format(i) })
end
local alive = 0
for i = 1, 199 do alive = alive + mp.live("user-data/r" .. i) end
T.eq(alive, 0, "no observer left for the old properties")
T.eq(mp.live("user-data/r200"), 1, "one for the one in use")
T.eq(#logs("warn", "properties in conditions"), 0, "the limit counts each reading on its own")
mp.fire("user-data/r200", "yes")
T.eq(click(42, 680), "cycle pause", "the last condition works")
mp.fire("user-data/r200", "0")
mp.advance(1)
T.eq(click(42, 680), nil, "and the string 0 hides it")
mp.set_opts({ controls = "<fullscreen>pause" })
mp.set_opts({ controls = "pause" })
T.eq(mp.live("fullscreen"), 1, "a property a module also watches keeps that module's observer")
mp.set_opts({ controls = "<fullscreen>pause" })
T.eq(mp.live("fullscreen"), 2, "watched again: a new observer for the condition")
mp.fire("fullscreen", true)
T.eq(click(42, 680), "cycle pause", "and it follows the property")

-- Many chapters do not turn the timeline off ------------------------------
start()
mp.fire("osd-dimensions", { w = 3840, h = 2160 })
local five = {}
for i = 1, 5000 do five[i] = { time = i * 100 / 5001 } end
mp.fire("chapter-list", five)
mp.mouse(1000, 2085)
mp.advance(1)
T.check(mods().alive(mods().timeline), "5000 chapters at 3840 px: the timeline is alive")
T.eq(#logs("error"), 0, "no error")
T.check(#painted() < 65536 and painted():find("m 0 ", 1, true) ~= nil, "and it is drawn")

-- The timeline comes back with the next file
start()
local tl = mods().timeline
local render = tl.render
tl.render = function() error("broken") end
mp.mouse(640, 690)
mp.advance(1)
T.check(not mods().alive(tl), "a failed timeline is off")
tl.render = render
mp.emit("file-loaded")
mp.advance(1)
T.check(mods().alive(tl), "file-loaded brings it back")
T.check(painted():find("m 0 ", 1, true) ~= nil, "drawn again")

-- While off, the timeline missed changes: back on, it gets the last values
start()
tl = mods().timeline
render = tl.render -- this instance's own
mp.fire("chapter-list", { { time = 20 } }) -- x 256
tl.render = function() error("broken") end
mp.mouse(640, 690)
mp.advance(1)
mp.fire("chapter-list", { { time = 50 } }) -- x 640, while it is off
tl.render = render
mp.emit("file-loaded")
mp.mouse(641, 690)
mp.advance(1)
T.check(painted():find("m 2556 ", 1, true) ~= nil, "revived: the new chapter mark")
T.check(painted():find("m 1020 ", 1, true) == nil, "and not the old one")

-- A module that fails mid drag drops it: no pause or seek timer left
start({ pause_on_drag = true })
mp.fire("pause", false)
mp.mouse(640, 645)
mp.button("down")
T.eq(mp.props.pause, true, "paused by the drag")
tl = mods().timeline
tl.render = function() error("broken") end
mp.advance(1)
T.check(not tl.dragging(), "the failed timeline dropped its drag")
T.eq(mp.props.pause, false, "and gave the pause back")
mp.advance(1)
T.eq(mp.active_timers(), 0, "no seek timer left")
tl.render = render

-- Each module has its own ctx: a watch made outside init is protected too
start()
local fs = package.loaded["modules.fullscreen"]
local got = 0
mods().watch("mute", "bool", function() got = got + 1 end)
mods().ctx_of(fs).watch("mute", "bool", function() error("late") end)
mods().watch("mute", "bool", function() got = got + 1 end)
mp.fire("mute", true)
T.check(not mods().alive(fs), "a late watch that fails turns its module off")
T.eq(got, 2, "the other observers still get the value")
mods().watch("mute", "bool", function() error("core") end)
mp.fire("mute", false)
mp.fire("mute", true)
T.eq(#logs("error", "observer of mute"), 1, "a core observer that fails is logged once")
T.eq(got, 6, "and does not stop the others")

-- ctx.unwatch only stops the module's own watches
start()
local calls = 0
local mine = mods().ctx_of(package.loaded["modules.pause"]).watch("mute", "bool", function() calls = calls + 1 end)
mods().ctx_of(package.loaded["modules.time"]).unwatch(mine)
mp.fire("mute", true)
T.eq(calls, 1, "another module cannot stop it")
mods().ctx_of(package.loaded["modules.pause"]).unwatch(mine)
mp.fire("mute", false)
T.eq(calls, 1, "its own module can")

-- The command buttons of old controls options are freed
start()
local probe = setmetatable({}, { __mode = "k" })
for r = 1, 300 do
    local t = {}
    for i = 1, 32 do t[i] = ("command:x:show-text %d_%d"):format(r, i) end
    mp.set_opts({ controls = table.concat(t, ",") })
    for _, e in ipairs(mods().row()) do probe[e.mod] = true end
    mods().call(mods().row()[1].mod, "press")
end
mp.set_opts({ controls = "pause" })
mp.mouse(640, 300) -- the zone under the cursor is not a button any more
for _ = 1, 5 do collectgarbage("collect") end
local left = 0
for _ in pairs(probe) do left = left + 1 end
T.eq(left, 0, "after 300 reloads no old command button is left in memory")

-- ctx.relayout: a module whose width changed moves the zones at once
start()
mp.mouse(130, 680) -- on the time
local pause = package.loaded["modules.pause"]
local width = pause.width
pause.width = function() return 120 end
mods().ctx_of(pause).relayout()
mp.commands = {}
mp.button("press")
T.eq(last_cmd(), "cycle pause", "the wider pause button is under the cursor, without moving it")
pause.width = width

-- A render that returns nil draws nothing and is not a failure
start()
package.loaded["modules.fullscreen"].render = function() end
mp.mouse(640, 690)
mp.advance(1)
T.check(mods().alive(package.loaded["modules.fullscreen"]), "nil from render is fine")
T.eq(#logs("error"), 0, "no error")

-- on_controls: the cursor on any module of the row ------------------------
start({ controls = "command:x:set pause yes,space,fullscreen" })
local function input(x, y) mp.mouse(x, y); return mouse().input(mp.now) end
T.eq(input(42, 680).on_controls, true, "on a command button")
T.eq(input(42, 680).on_bar, false, "not on the bar")
T.eq(input(640, 680).on_controls, false, "in the empty middle")
T.eq(input(1240, 680).on_controls, true, "on the fullscreen button on the right")
T.eq(input(640, 645).on_bar, true, "on the bar, above the row")
T.eq(input(640, 645).on_controls, false, "and not on the row")
T.eq(input(640, 710).on_bar, false, "under the row: not on the bar")

T.done("test_modules")
