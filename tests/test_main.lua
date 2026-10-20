-- Runs main.lua against a fake mp and checks the behaviour end to end:
-- painting, bindings, seeking and timers.
local T = require "lib"

local function start(script_opts)
    T.unload()
    mp = T.fake_mp({ ["mpv-version"] = "mpv v0.40.0" })
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = 1280, h = 720 })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.fire("mouse-pos", { x = 0, y = 0, hover = true }) -- Linux start-up value
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

local function press(event, canceled)
    mp.bindings["suji-bar"].fn({ event = event, canceled = canceled })
end

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
mp.fire("mouse-pos", { x = 640, y = 300, hover = true })
mp.advance(0.5)
T.eq(mp.bindings["suji-bar"], nil, "far away: no bindings")
mp.fire("mouse-pos", { x = 640, y = 650, hover = true })
mp.advance(0.5)
T.eq(mp.bindings["suji-bar"], nil, "near but outside the zone: no bindings")
local near = mp.updates[#mp.updates].data
mp.fire("mouse-pos", { x = 640, y = 710, hover = true })
T.check(mp.bindings["suji-bar"] ~= nil, "bindings on as soon as the cursor enters")
T.check(mp.bindings["suji-bar-dbl"] ~= nil, "double click swallowed on the bar")
T.eq(mp.bindings["suji-bar"].flags.complex, true, "complex binding for drag")
mp.advance(0.5)
T.check(mp.updates[#mp.updates].data ~= near, "bar grows in the zone")
mp.advance(5)
T.eq(mp.active_timers(), 0, "idle timer fired once and stopped")

-- Click and drag --------------------------------------------------------
mp.commands = {}
press("down")
T.eq(last_seek()[2], "50.000", "click seeks to the cursor")
T.eq(last_seek()[3], "absolute+exact", "click seek is exact")
mp.fire("mouse-pos", { x = 768, y = 600, hover = true }) -- left the zone mid drag
T.check(mp.bindings["suji-bar"] ~= nil, "bindings stay while dragging")
mp.advance(0.05)
T.eq(last_seek()[2], "60.000", "drag seeks")
local before = seeks()
mp.fire("mouse-pos", { x = 769, y = 600, hover = true })
mp.fire("mouse-pos", { x = 770, y = 600, hover = true })
T.eq(seeks(), before, "drag seeks are rate limited")
mp.advance(0.1)
T.eq(seeks(), before + 1, "pending drag seek lands")
press("up")
T.eq(last_seek()[3], "absolute+exact", "release seeks exactly")
mp.advance(0.1)
T.eq(mp.bindings["suji-bar"], nil, "bindings off after release outside the zone")

-- Leaving the window ends a drag ----------------------------------------
mp.fire("mouse-pos", { x = 100, y = 710, hover = true })
press("down")
mp.fire("mouse-pos", { x = 100, y = 710, hover = false })
T.eq(mp.bindings["suji-bar"], nil, "leaving the window drops the bindings")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers after leaving")

-- pause_on_drag ---------------------------------------------------------
start({ pause_on_drag = true })
mp.fire("mouse-pos", { x = 640, y = 710, hover = true })
press("down")
T.eq(mp.props.pause, true, "paused while dragging")
press("up")
T.eq(mp.props.pause, false, "resumed after dragging")
mp.set_property_bool("pause", true)
press("down")
press("up")
T.eq(mp.props.pause, true, "stays paused if it was paused")

-- idle_line=no and no duration -----------------------------------------
start({ idle_line = false })
T.eq(mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "", "", "nothing at rest")
mp.fire("duration", nil)
mp.fire("mouse-pos", { x = 640, y = 710, hover = true })
T.eq(mp.bindings["suji-bar"], nil, "no duration: bar is not clickable")

-- A broken visibility function must not break the player ----------------
start()
package.loaded["visibility"].compute = function() error("oops") end
mp.fire("mouse-pos", { x = 640, y = 710, hover = true })
mp.advance(1)
T.eq(mp.bindings["suji-bar"], nil, "error counts as hidden")
T.eq(mp.logs[#mp.logs][1], "error", "error is reported")

-- Old mpv -----------------------------------------------------------------
T.unload()
mp = T.fake_mp({ ["mpv-version"] = "mpv 0.38.0" })
dofile("suji/main.lua")
T.eq(mp.logs[1] and mp.logs[1][1], "warn", "warns on mpv older than 0.39")

T.done("test_main")
