-- Runs main.lua against a fake mp and checks the behaviour end to end:
-- painting, bindings, seeking and timers.
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
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.mouse(0, 0) -- Linux start-up value
    mp.advance(1)
    return mp
end

local function last_seek()
    for i = #mp.commands, 1, -1 do
        if mp.commands[i][1] == "seek" then return mp.commands[i] end
    end
end

local function seeks()
    local n = 0
    for _, c in ipairs(mp.commands) do if c[1] == "seek" then n = n + 1 end end
    return n
end

local bar = function() return package.loaded["modules.timeline"] end

-- At rest ---------------------------------------------------------------
start()
T.check(#mp.updates >= 1, "paints the rest line")
T.check(mp.updates[#mp.updates].data ~= "", "rest line is not empty")
T.eq(mp.updates[#mp.updates].w, 1280, "overlay matches window width")
T.eq(mp.active_timers(), 0, "no timers at rest")
T.eq(mp.bindings["suji-bar"], nil, "no bindings at rest")
local n = #mp.updates
mp.fire("time-pos", 50.01) -- same pixel
mp.advance(1)
T.eq(#mp.updates, n, "no repaint inside the same pixel")
mp.fire("time-pos", 51)
mp.advance(1)
T.eq(#mp.updates, n + 1, "repaint when the progress moves a pixel")
T.eq(mp.active_timers(), 0, "still no timers after painting")

-- Approach and hover ----------------------------------------------------
mp.mouse(640, 300)
mp.advance(0.5)
T.eq(mp.bindings["suji-bar"], nil, "far away: no bindings")
mp.mouse(640, 600)
mp.advance(0.5)
T.eq(mp.bindings["suji-bar"], nil, "near but outside the zone: no bindings")
T.eq(mp.props["input-builtin-dragging"], true, "window dragging untouched off the bar")
local near = mp.updates[#mp.updates].data
mp.mouse(640, 645)
T.check(mp.bindings["suji-bar"] ~= nil, "bindings on as soon as the cursor enters")
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "double click swallowed on the bar")
T.eq(mp.bindings["suji-bar"].flags.complex, true, "complex binding for drag")
T.eq(mp.props["input-builtin-dragging"], false, "built-in dragging off on the bar")
mp.advance(0.5)
T.check(mp.updates[#mp.updates].data ~= near, "bar grows in the zone")
mp.advance(5)
T.eq(mp.active_timers(), 0, "idle timer fired once and stopped")

-- Click and drag --------------------------------------------------------
mp.commands = {}
mp.button("down")
T.eq(last_seek()[2], "50.000", "click seeks to the cursor")
T.eq(last_seek()[3], "absolute+exact", "click seek is exact")
mp.advance(0.1)
mp.mouse(651, 600) -- slowly, and out of the zone
T.check(bar().dragging(), "drag survives moving more than 3 px")
T.check(mp.bindings["suji-bar"] ~= nil, "bindings stay while dragging")
T.eq(last_seek()[2], "50.859", "drag seeks")
T.eq(last_seek()[3], "absolute+exact", "slow drag seeks exactly")
mp.advance(0.1)
mp.mouse(769, 600)
local before = seeks()
mp.mouse(770, 600)
T.eq(seeks(), before, "drag seeks are rate limited")
mp.advance(0.1)
T.eq(seeks(), before + 1, "pending drag seek lands")
mp.mouse(1280, 600)
mp.advance(0.04)
T.eq(last_seek()[3], "absolute+keyframes", "fast drag seeks by keyframes")
mp.mouse(1500, 600) -- past the right edge
mp.advance(0.1)
T.eq(last_seek()[2], "99.500", "drag stops short of the end")
mp.button("up")
T.eq(last_seek()[2], "99.500", "release stays short of the end")
T.eq(last_seek()[3], "absolute+exact", "release seeks exactly")
mp.advance(0.1)
T.eq(mp.bindings["suji-bar"], nil, "bindings off after release outside the zone")
T.eq(mp.props["input-builtin-dragging"], true, "built-in dragging restored")

-- A click without moving seeks once -------------------------------------
mp.mouse(320, 645)
mp.commands = {}
mp.button("down")
mp.button("up")
T.eq(seeks(), 1, "click without movement: a single exact seek")
mp.commands = {}
mp.button("press")
T.eq(seeks(), 1, "press event works as a click")
T.check(not bar().dragging(), "press event leaves no drag behind")

-- Lost or canceled button up -------------------------------------------
mp.button("down")
mp.button("down") -- the up got lost
T.check(bar().dragging(), "a new down starts a new drag")
mp.commands = {}
mp.mouse(400, 645)
mp.advance(0.1)
mp.button("up", true)
T.check(not bar().dragging(), "canceled up ends the drag")
local s = seeks()
T.eq(s, 1, "canceled up adds no final seek")

-- Resize and file change during a drag ----------------------------------
mp.button("down")
mp.fire("osd-dimensions", { w = 1000, h = 600 })
T.check(not bar().dragging(), "resize ends the drag")
mp.mouse(500, 525) -- the bar's zone is 514 to 538 now
mp.button("down")
mp.commands = {}
mp.emit("end-file")
T.check(not bar().dragging(), "end-file drops the drag")
T.eq(seeks(), 0, "dropped drag does not seek")
mp.button("down")
mp.fire("duration", 200)
T.check(bar().dragging(), "a growing duration keeps the drag")
mp.fire("duration", nil)
T.check(not bar().dragging(), "unknown duration drops the drag")
mp.fire("duration", 200)
mp.fire("duration", 1 / 0)
mp.mouse(500, 525)
T.eq(mp.bindings["suji-bar"], nil, "infinite duration: not clickable")

-- Leaving the window ends a drag ----------------------------------------
start()
mp.mouse(100, 645)
mp.button("down")
mp.mouse(100, 645, false)
T.check(not bar().dragging(), "leaving the window ends the drag")
T.eq(mp.bindings["suji-bar"], nil, "leaving the window drops the bindings")
mp.advance(0.5) -- let the last paint and fade finish
T.eq(mp.active_timers(), 0, "idle timer off after leaving")

-- Idle: compute is asked again after hide_delay -------------------------
start({ hide_delay = 2 })
local calls = {}
package.loaded["core.visibility"].compute = function(input)
    calls[#calls + 1] = input.idle_time
    return input.idle_time >= input.hide_delay and 0 or 1
end
mp.mouse(640, 400)
local count = #calls
mp.advance(1.9)
mp.advance(0.3)
T.check(#calls > count, "compute called again after hide_delay")
T.check(calls[#calls] >= 2, "idle_time has reached hide_delay")
mp.advance(0.5)
T.eq(mp.active_timers(), 0, "no timers once hidden")

-- pause_on_drag ---------------------------------------------------------
start({ pause_on_drag = true })
mp.mouse(640, 645)
mp.button("down")
T.eq(mp.props.pause, true, "paused while dragging")
mp.button("up")
T.eq(mp.props.pause, false, "resumed after dragging")
mp.set_property_bool("pause", true)
mp.button("down")
mp.button("up")
T.eq(mp.props.pause, true, "stays paused if it was paused")
mp.set_property_bool("pause", false)
mp.button("down")
mp.set_property_bool("pause", false) -- unpaused by hand mid drag
mp.set_property_bool("pause", true)
mp.set_property_bool("pause", false)
mp.button("up")
T.eq(mp.props.pause, false, "a manual unpause is not overwritten")

-- The user's own input-builtin-dragging=no is left alone ----------------
start(nil, { ["input-builtin-dragging"] = false })
mp.mouse(640, 645)
mp.mouse(640, 300)
T.eq(mp.props["input-builtin-dragging"], false, "user setting kept")
start()
mp.mouse(640, 645)
mp.emit("shutdown")
T.eq(mp.props["input-builtin-dragging"], true, "restored on shutdown")

-- idle_line=no and no duration -----------------------------------------
start({ idle_line = false })
T.eq(mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "", "", "nothing at rest")
local quiet = #mp.updates
mp.fire("time-pos", 80)
mp.advance(1)
T.eq(#mp.updates, quiet, "hidden bar: no repaint per pixel")
T.eq(mp.active_timers(), 0, "hidden bar: no timers")
mp.fire("duration", nil)
mp.mouse(640, 645)
T.eq(mp.bindings["suji-bar"], nil, "no duration: bar is not clickable")

-- A broken visibility function must not break the player ----------------
start()
package.loaded["core.visibility"].compute = function() error("oops") end
mp.mouse(640, 645)
mp.advance(1)
T.eq(mp.bindings["suji-bar"], nil, "error counts as hidden")
T.eq(mp.logs[#mp.logs][1], "error", "error is reported")

-- Options are kept in range ---------------------------------------------
start({ hide_delay = 1e9, proximity = 1e9, scale = 0 / 0 })
local o = package.loaded["core.options"]
T.eq(o.hide_delay, 3600, "hide_delay capped")
T.eq(o.proximity, 10000, "proximity capped")
T.eq(o.scale, 1, "NaN scale falls back")

-- The default row of 0.2.0 to 0.6.1 counts as not set -------------------
local OLD = "pause,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen"
local NEW = "pause,prev,next,volume,time,space,subtitles,audio,playlist,speed,more,fullscreen"
local function old_logs()
    local n = 0
    for _, l in ipairs(mp.logs) do if tostring(l[2]):find("^controls: the default row of suji 0%.2%.0") then n = n + 1 end end
    return n
end
start({ controls = OLD, debug = true })
o = package.loaded["core.options"]
T.eq(o.controls, NEW, "the old row exactly: today's default")
T.eq(old_logs(), 1, "logged with debug")
local function x0_of(name)
    for _, b in ipairs(package.loaded["core.layout"].current().boxes) do
        if package.loaded["core.modules"].name_of(b.mod) == name then return b.x0 end
    end
end
T.eq(x0_of("volume"), 72, "and the row is today's: the volume on the left")
mp.set_opts({ scale = 1.5 })
T.eq(old_logs(), 1, "logged once, not on every change of options")
start({ controls = OLD })
T.eq(package.loaded["core.options"].controls, NEW, "without debug too")
T.eq(old_logs(), 0, "and then nothing is logged")
for _, s in ipairs({ "  " .. OLD .. " ", OLD .. "\r", "\t" .. OLD .. "\n" }) do
    start({ controls = s })
    T.eq(package.loaded["core.options"].controls, NEW, ("only spaces around it: %q"):format(s))
end
for _, s in ipairs({
    "pause,time,space,subtitles,audio,playlist,speed,more,fullscreen,volume", -- another order
    "pause,time,space,subtitles,audio,playlist,speed,more,volume",            -- one less
    "pause,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen,gap",
    "pause, time,space,subtitles,audio,playlist,speed,more,volume,fullscreen", -- a space inside
    "PAUSE,time,space,subtitles,audio,playlist,speed,more,volume,fullscreen",
}) do
    start({ controls = s, debug = true })
    T.eq(package.loaded["core.options"].controls, s, "a row with a change is kept: " .. s)
    T.eq(old_logs(), 0, "and nothing is logged")
end
-- At run time
start({ debug = true })
o = package.loaded["core.options"]
mp.set_opts({ controls = "pause,space,fullscreen" })
T.eq(o.controls, "pause,space,fullscreen", "at run time: a row of one's own")
mp.set_opts({ controls = OLD })
T.eq(o.controls, NEW, "at run time: the old row is today's default")
T.eq(x0_of("volume"), 72, "and laid out at once")
T.eq(old_logs(), 1, "logged")
mp.set_opts({ controls = OLD:gsub(",fullscreen$", "") })
T.eq(o.controls, (OLD:gsub(",fullscreen$", "")), "at run time: a changed one is kept")
mp.set_opts({ controls = OLD })
T.eq(old_logs(), 2, "back to the old row: logged again")

-- docs/suji.conf sets nothing, and shows every default ----------------------
start()
o = package.loaded["core.options"]
local f = assert(io.open("docs/suji.conf", "rb"))
local conf = f:read("*a")
f:close()
local shown = {}
for line in (conf .. "\n"):gmatch("([^\n]*)\n") do
    T.check(line == "" or line:sub(1, 1) == "#", "docs/suji.conf: no active line: " .. line)
    local k, v = line:match("^#([a-z_]+)=(.*)$")
    if k then shown[k] = v end
end
local nopts = 0
for k, v in pairs(o) do
    if type(v) ~= "function" and type(v) ~= "table" then
        nopts = nopts + 1
        local want = type(v) == "boolean" and (v and "yes" or "no") or tostring(v)
        T.eq(shown[k], want, "docs/suji.conf: #" .. k .. "= shows the default")
    end
end
T.eq(nopts, 11, "every option")

-- Controls ----------------------------------------------------------------
local function last_cmd() local c = mp.commands[#mp.commands]; return c and table.concat(c, " ") end
local function painted() return mp.updates[#mp.updates].data end

-- At rest the time does not repaint, even when its text changes.
start()
mp.fire("duration", 10000) -- 0.128 px per second
mp.advance(1)
n = #mp.updates
mp.fire("time-pos", 51)
mp.advance(1)
T.eq(#mp.updates, n, "at rest: a new second alone does not repaint")
mp.fire("pause", true) -- paused: everything shows
mp.advance(1)
T.check(painted():find("}0:00:51{", 1, true) ~= nil, "time shown while paused")
n = #mp.updates
mp.fire("time-pos", 52)
mp.advance(0.1)
T.eq(#mp.updates, n + 1, "shown: a new second repaints")
mp.fire("time-pos", 52.5)
mp.advance(0.1)
T.eq(#mp.updates, n + 1, "same second, same pixel: no repaint")
T.eq(mp.active_timers(), 0, "controls leave no timers behind")

start()
mp.fire("media-title", "Movie")
mp.fire("volume", 100)
local seen
package.loaded["core.visibility"].compute = function(input) seen = input.on_controls; return 1 end
mp.mouse(42, 680)
T.eq(seen, true, "visibility knows the cursor is on a control")
T.check(mp.bindings["suji-bar"] ~= nil, "bindings on over the pause button")
T.eq(mp.props["input-builtin-dragging"], false, "built-in dragging off over a button")
T.eq(mp.bindings["suji-wheel-up"], nil, "wheel left alone over pause")
mp.commands = {}
mp.button("down"); mp.button("up")
T.eq(last_cmd(), "cycle pause", "pause button")
T.eq(seeks(), 0, "pause button does not seek")
mp.advance(1)
T.check(painted():find("}Movie", 1, true) ~= nil, "media-title shown")
mp.mouse(150, 680)
mp.button("down"); mp.button("up")
mp.advance(0.1)
T.check(painted():find(" / -00:50", 1, true) ~= nil, "click on the time shows the remaining time")
mp.mouse(94, 680)
mp.button("press")
T.eq(last_cmd(), "cycle mute", "volume icon mutes")
T.check(mp.bindings["suji-wheel-up"] ~= nil, "wheel bound over the volume icon")
mp.bindings["suji-wheel-up"].fn()
T.eq(last_cmd(), "add volume 5", "wheel up")
mp.bindings["suji-wheel-down"].fn()
T.eq(last_cmd(), "add volume -5", "wheel down")
mp.advance(0.3) -- the slider unfolds: from 116 to 180
mp.mouse(148, 680)
mp.button("down")
T.eq(last_cmd(), "set volume 51", "click on the slider")
mp.mouse(50, 600) -- drag past the start and out of the zone
T.eq(last_cmd(), "set volume 0", "drag on the slider")
T.check(mp.bindings["suji-bar"] ~= nil, "bindings stay while dragging the volume")
mp.button("up")
mp.mouse(1238, 680)
mp.button("press")
T.eq(last_cmd(), "cycle fullscreen", "fullscreen button")
mp.mouse(640, 680)
T.eq(mp.bindings["suji-bar"], nil, "empty middle of the row: nothing bound")
T.eq(mp.bindings["suji-wheel-up"], nil, "wheel released")
T.eq(mp.props["input-builtin-dragging"], true, "built-in dragging back")

-- Hidden controls take no clicks
start()
package.loaded["core.visibility"].compute = function() return 0 end
mp.mouse(42, 680)
T.eq(mp.bindings["suji-bar"], nil, "hidden: the pause button is not clickable")

-- Tooltip and two-line title
start()
mp.fire("media-title", "Movie")
mp.mouse(320, 645)
mp.advance(1)
T.check(painted():find("}00:25", 1, true) ~= nil, "time under the cursor")
mp.messages["set-title"]("Show", "Ep {1}")
mp.advance(1)
T.check(painted():find("}SHOW", 1, true) ~= nil, "series from set-title")
T.check(painted():find("}Ep \\{1\\}", 1, true) ~= nil, "episode from set-title, escaped")
T.check(painted():find("}Movie", 1, true) == nil, "media-title replaced")
mp.messages["set-title"]("", "")
mp.advance(1)
T.check(painted():find("}Movie", 1, true) ~= nil, "empty set-title goes back to media-title")
mp.messages["set-title"](string.rep("\195\169", 300), nil)
T.eq(package.loaded["core.state"].series, string.rep("\195\169", 200), "long titles are cut by characters")
T.eq(package.loaded["core.state"].episode, nil, "missing argument")
mp.advance(1)
T.check(painted():find("}\195\169", 1, true) ~= nil, "a single part shows on one line")
mp.emit("end-file")
T.eq(package.loaded["core.state"].series, nil, "end-file clears the title")

-- Someone else turns window dragging back on while suji has it off
start()
mp.mouse(640, 645)
local writes = 0
local set = mp.set_property_bool
mp.set_property_bool("input-builtin-dragging", true)
mp.set_property_bool = function(...) writes = writes + 1; return set(...) end
mp.mouse(640, 300)
T.eq(mp.props["input-builtin-dragging"], true, "a change made meanwhile is kept")
T.eq(writes, 0, "and not written again")

-- At rest, cache and chapter changes do not repaint
start({ idle_line = false })
n = #mp.updates
mp.fire("demuxer-cache-state", { ["seekable-ranges"] = { { start = 0, ["end"] = 90 } } })
mp.fire("chapter-list", { { time = 10 } })
mp.fire("media-title", "x")
mp.advance(1)
T.eq(#mp.updates, n, "hidden: cache, chapters and title do not repaint")

-- Huge or broken titles are cut
start()
mp.fire("media-title", string.rep("a", 1000000))
T.eq(#package.loaded["core.state"].title, 200, "media-title is cut too")
mp.messages["set-title"](string.rep("\128", 5000), "x")
T.eq(#package.loaded["core.state"].series, 200, "stray UTF-8 bytes do not skip the cut")

-- Measuring: real results are cached, guesses are not
start()
local measure = package.loaded["core.painter"].measure
mp.probes = 0
T.eq(measure("a", 7), 7, "no bounds: the guess")
measure("a", 7)
T.eq(mp.probes, 2, "a guess is not cached")
mp.probe_result = { x0 = 0, x1 = 30, y0 = 0, y1 = 10 }
T.eq(measure("b", 7), 30, "measured width")
measure("b", 7)
T.eq(mp.probes, 3, "a measured width is cached")

-- On the timeline the row shows the time under the cursor
start()
mp.fire("pause", true)
mp.mouse(320, 645)
mp.advance(1)
T.check(painted():find("\\1a&H66&\\3a&H94&\\4a&HC2&}00:25{", 1, true) ~= nil, "time under the cursor, dimmed")
T.check(painted():find("} / 01:40", 1, true) ~= nil, "duration unchanged")
mp.mouse(640, 300)
mp.advance(1)
T.check(painted():find("}00:50{", 1, true) ~= nil, "back to the real time off the bar")

-- A resize ends a volume drag
start()
mp.fire("volume", 100)
mp.mouse(94, 680)
mp.advance(0.3)
mp.mouse(148, 680)
mp.button("down")
mp.fire("osd-dimensions", { w = 1000, h = 600 })
mp.commands = {}
mp.mouse(50, 600)
T.eq(#mp.commands, 0, "no volume change after the resize")

-- Options changed at run time ---------------------------------------------
start({ debug = true })
o = package.loaded["core.options"]
local st = package.loaded["core.state"]
mp.set_opts({ scale = 1.5 })
T.eq(st.scale, 1.5, "scale applied at run time")
T.check(mp.logs[#mp.logs][2]:find("^options: .*scale 1%.500") ~= nil, "new scale logged")
mp.set_opts({ scale = 1e9, hide_delay = -5, proximity = 0 / 0, accent = "nope" })
T.eq(o.scale, 8, "reload: scale capped")
T.eq(o.hide_delay, 0, "reload: hide_delay floored")
T.eq(o.proximity, 120, "reload: NaN proximity falls back")
T.eq(o.accent, "ffffff", "reload: invalid accent falls back")
local warned = false
for _, l in ipairs(mp.logs) do warned = warned or (l[1] == "warn" and l[2]:find("accent") ~= nil) end
T.check(warned, "reload: invalid accent warned")
mp.set_opts({ scale = 1, hide_delay = 1.5, accent = "ff0000" })
local function accent_warnings()
    local n = 0
    for _, l in ipairs(mp.logs) do if l[1] == "warn" and l[2]:find("accent") then n = n + 1 end end
    return n
end
local before_bad = accent_warnings()
mp.set_opts({ accent = "nope" })
T.eq(accent_warnings(), before_bad + 1, "the same bad accent after a good one: warned again")
mp.set_opts({ remaining_time = true })
mp.set_opts({ remaining_time = false })
T.eq(accent_warnings(), before_bad + 1, "but only once while it stays bad")
mp.set_opts({ accent = "ff0000" })
mp.fire("pause", true)
mp.advance(1)
T.check(painted():find("&H0000FF&", 1, true) ~= nil, "new accent painted")
mp.set_opts({ remaining_time = true })
T.eq(st.remaining, true, "remaining_time applied at run time")
mp.advance(0.1)
T.check(painted():find(" / -00:50", 1, true) ~= nil, "remaining time painted")
start({ idle_line = false })
n = #mp.updates
mp.set_opts({ idle_line = true })
mp.advance(0.1)
T.eq(#mp.updates, n + 1, "idle_line on at run time repaints")
T.check(painted() ~= "", "rest line back")
T.eq(mp.active_timers(), 0, "reload leaves no timers")

-- An invalid accent from outside: cut, no control characters, warned once
start()
local function warns()
    local w = {}
    for _, l in ipairs(mp.logs) do if l[1] == "warn" then w[#w + 1] = l[2] end end
    return w
end
mp.set_opts({ accent = "\27[31m\7\194\155x\155" .. string.rep("z", 100) })
local w = warns()
T.eq(#w, 1, "invalid accent warned")
T.check(not w[1]:find("[%z\1-\31\127]") and not w[1]:find("\194[\128-\159]") and not w[1]:find("\155"),
    "accent warning has no control characters")
T.check(#w[1] < 80, "accent warning is cut")
mp.set_opts({ scale = 2 })
T.eq(#warns(), 1, "the same invalid accent is not warned again")

-- hide_delay changed while the idle timer runs
start({ hide_delay = 1 })
mp.mouse(640, 400)
mp.advance(0.5)
mp.set_opts({ hide_delay = 3 })
mp.advance(1)
T.check(mp.active_timers() > 0, "longer hide_delay: idle timer still pending")
mp.advance(2)
T.eq(mp.active_timers(), 0, "longer hide_delay: idle timer fired")
T.eq(package.loaded["core.mouse"].target(mp.now), 0, "hidden after the new hide_delay")
start({ hide_delay = 3 })
mp.mouse(640, 400)
mp.advance(0.5)
mp.set_opts({ hide_delay = 1 })
mp.advance(0.6)
T.eq(package.loaded["core.mouse"].target(mp.now), 0, "shorter hide_delay hides on time")
T.eq(mp.active_timers(), 0, "shorter hide_delay: no timer left")

-- enabled and mpv's OSC -------------------------------------------------
start(nil, { osc = true })
T.eq(mp.props.osc, false, "OSC turned off at start")
mp.mouse(640, 645)
mp.button("down")
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, true, "disabled: OSC back on")
T.check(not bar().dragging(), "disabled: drag dropped")
T.eq(mp.bindings["suji-bar"], nil, "disabled: no bindings")
T.eq(mp.props["input-builtin-dragging"], true, "disabled: window dragging back")
mp.advance(0.5)
T.eq(painted(), "", "disabled: nothing on screen")
n = #mp.updates
mp.mouse(640, 646)
mp.fire("time-pos", 80)
mp.fire("pause", true)
mp.advance(1)
T.eq(#mp.updates, n, "disabled: no repaint")
T.eq(mp.bindings["suji-bar"], nil, "disabled: the bar takes no clicks")
T.eq(mp.active_timers(), 0, "disabled: no timers")
mp.set_opts({ enabled = true })
T.eq(mp.props.osc, false, "enabled again: OSC off")
T.check(mp.bindings["suji-bar"] ~= nil, "enabled again: a still cursor on the bar is seen")
mp.advance(1)
T.check(painted() ~= "", "enabled again: painted")
start()
mp.fire("pause", true)
mp.advance(1)
mp.set_opts({ enabled = false })
mp.fire("pause", false)
mp.mouse(640, 100)
mp.set_opts({ enabled = true })
mp.advance(0.01)
T.check(painted():find("}00:50", 1, true) == nil, "enabled again: no fade out of old controls")

start({ enabled = false }, { osc = true })
T.eq(mp.props.osc, true, "disabled from the start: OSC untouched")
T.eq(mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "", "", "disabled from the start: nothing drawn")
start(nil, { osc = false })
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, false, "OSC the user turned off stays off")
start(nil, { osc = true })
mp.set_property_bool("osc", true) -- turned back on by the user
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, true, "OSC the user turned on stays on")
start(nil, { osc = true })
mp.set_property_bool("osc", true) -- the user turns it on
mp.set_property_bool("osc", false) -- and off again, by hand
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, false, "OSC set by hand after suji took it: suji no longer gives it back")
mp.set_opts({ enabled = true })
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, false, "nor later")
start(nil, { osc = true })
mp.advance(1)
mp.set_opts({ enabled = false })
T.eq(mp.props.osc, true, "suji's own write is not taken for the user's: the OSC comes back")

-- File name without the extension -----------------------------------------
start()
mp.fire("pause", true)
mp.fire("filename", "Bills Must Be Paid part 1.mp4")
mp.fire("filename/no-ext", "Bills Must Be Paid part 1")
mp.fire("media-title", "Bills Must Be Paid part 1.mp4")
mp.advance(1)
T.check(painted():find("}Bills Must Be Paid part 1$") ~= nil, "file name shown without extension")
mp.fire("media-title", string.rep("b", 1000))
T.eq(package.loaded["core.state"].title, string.rep("b", 200), "a title tag is cut, never raw")

-- set-title: one part, and a clean debug log -------------------------------
start({ debug = true })
mp.messages["set-title"]("Episode 5")
T.eq(package.loaded["core.state"].series, "Episode 5", "a single argument")
T.eq(package.loaded["core.state"].episode, nil, "no second argument")
mp.fire("pause", true)
mp.advance(1)
T.check(painted():find("}Episode 5", 1, true) ~= nil and painted():find("}EPISODE 5", 1, true) == nil,
    "a single argument: one line")
mp.messages["set-title"]("", "Episode 5")
T.eq(package.loaded["core.state"].episode, "Episode 5", "episode alone")
T.eq(package.loaded["core.state"].series, nil, "no series")
mp.messages["set-title"]("a\27[31mb\194\155c", "\7")
local line = mp.logs[#mp.logs][2]
T.check(not line:find("%c") and not line:find("\194[\128-\159]"), "no control characters in the log")
T.check(line:find("a?[31mb??c", 1, true) ~= nil, "the rest of the text is kept")

-- set-title with two and with three parts ------------------------------------
start({ debug = true })
mp.fire("pause", true)
mp.messages["set-title"]("Show", "Episode 2")
mp.advance(1)
local st2 = package.loaded["core.state"]
T.eq(st2.episode_name, nil, "two parts: no name")
T.check((painted() .. "\n"):find("\\an7\\pos%(32%.0,24%.0%)[^\n]*}SHOW\n") ~= nil, "the series at the top left")
T.check((painted() .. "\n"):find("\\an7\\pos%(32%.0,44%.0%)[^\n]*\\b1[^\n]*}Episode 2\n") ~= nil, "the episode under it, in bold")
local _, events = painted():gsub("}Episode 2", "")
T.eq(events, 1, "and nothing after it")
mp.messages["set-title"]("Show", "Episode 2", "The {name}")
T.eq(st2.episode_name, "The {name}", "three parts: the name")
T.eq(mp.logs[#mp.logs][2], "set-title: Show / Episode 2 / The {name}", "logged with the name")
mp.advance(1)
local name_x = (painted() .. "\n"):match("\\an7\\pos%(([%d.]+),44%.0%)[^\n]*\\b0[^\n]*\\1a&H66&[^\n]*}The \\{name\\}\n")
T.check(name_x ~= nil, "the name on the episode's line, not bold, in grey (60 %), escaped")
T.check(name_x and tonumber(name_x) > 32 + 10, "after the episode")
T.check((painted() .. "\n"):find("}SHOW\n") ~= nil and (painted() .. "\n"):find("}Episode 2\n") ~= nil, "series and episode as before")
mp.messages["set-title"]("", "Episode 2", "The name")
mp.advance(1)
T.check((painted() .. "\n"):find("\\an7\\pos%(32%.0,24%.0%)[^\n]*}Episode 2\n") ~= nil, "no series: the episode on the first line")
T.check((painted() .. "\n"):find("}The name\n") ~= nil, "with its name")
mp.messages["set-title"]("Show", "", "The name")
mp.advance(1)
T.eq(st2.episode_name, "The name", "kept")
T.check((painted() .. "\n"):find("}The name", 1, true) == nil, "but only shown with an episode")
mp.messages["set-title"]("Show", "Episode 2", string.rep("\195\169", 300))
T.eq(st2.episode_name, string.rep("\195\169", 200), "the name is cut too")
mp.messages["set-title"]("Show", "Episode 2", "")
T.eq(st2.episode_name, nil, "an empty name: none")
mp.messages["set-title"]("Show", "Episode 2", "x")
mp.emit("end-file")
T.eq(st2.episode_name, nil, "end-file clears the name")

-- Old mpv -----------------------------------------------------------------
T.unload()
mp = T.fake_mp({ ["mpv-version"] = "mpv 0.38.0" })
dofile("suji/main.lua")
T.eq(mp.logs[1] and mp.logs[1][1], "warn", "warns on mpv older than 0.39")

T.done("test_main")
