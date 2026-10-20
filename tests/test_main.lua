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

local bar = function() return package.loaded["elements.bar"] end

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
mp.mouse(640, 650)
mp.advance(0.5)
T.eq(mp.bindings["suji-bar"], nil, "near but outside the zone: no bindings")
T.eq(mp.props["input-builtin-dragging"], true, "window dragging untouched off the bar")
local near = mp.updates[#mp.updates].data
mp.mouse(640, 710)
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
mp.mouse(320, 710)
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
mp.mouse(400, 710)
mp.advance(0.1)
mp.button("up", true)
T.check(not bar().dragging(), "canceled up ends the drag")
local s = seeks()
T.eq(s, 1, "canceled up adds no final seek")

-- Resize and file change during a drag ----------------------------------
mp.button("down")
mp.fire("osd-dimensions", { w = 1000, h = 600 })
T.check(not bar().dragging(), "resize ends the drag")
mp.mouse(500, 590)
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
mp.mouse(500, 595)
T.eq(mp.bindings["suji-bar"], nil, "infinite duration: not clickable")

-- Leaving the window ends a drag ----------------------------------------
start()
mp.mouse(100, 710)
mp.button("down")
mp.mouse(100, 710, false)
T.check(not bar().dragging(), "leaving the window ends the drag")
T.eq(mp.bindings["suji-bar"], nil, "leaving the window drops the bindings")
mp.advance(0.5) -- let the last paint and fade finish
T.eq(mp.active_timers(), 0, "idle timer off after leaving")

-- Idle: compute is asked again after hide_delay -------------------------
start({ hide_delay = 2 })
local calls = {}
package.loaded["visibility"].compute = function(input)
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
mp.mouse(640, 710)
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
mp.mouse(640, 710)
mp.mouse(640, 300)
T.eq(mp.props["input-builtin-dragging"], false, "user setting kept")
start()
mp.mouse(640, 710)
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
mp.mouse(640, 710)
T.eq(mp.bindings["suji-bar"], nil, "no duration: bar is not clickable")

-- A broken visibility function must not break the player ----------------
start()
package.loaded["visibility"].compute = function() error("oops") end
mp.mouse(640, 710)
mp.advance(1)
T.eq(mp.bindings["suji-bar"], nil, "error counts as hidden")
T.eq(mp.logs[#mp.logs][1], "error", "error is reported")

-- Options are kept in range ---------------------------------------------
start({ hide_delay = 1e9, proximity = 1e9, scale = 0 / 0 })
local o = package.loaded["options"]
T.eq(o.hide_delay, 3600, "hide_delay capped")
T.eq(o.proximity, 10000, "proximity capped")
T.eq(o.scale, 1, "NaN scale falls back")

-- Old mpv -----------------------------------------------------------------
T.unload()
mp = T.fake_mp({ ["mpv-version"] = "mpv 0.38.0" })
dofile("suji/main.lua")
T.eq(mp.logs[1] and mp.logs[1][1], "warn", "warns on mpv older than 0.39")

T.done("test_main")
