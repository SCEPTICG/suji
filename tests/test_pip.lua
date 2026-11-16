-- Picture in picture (core/pip.lua), driven through main.lua and the fake
-- mp: the three ways of moving the window (mpv, mpv.net, any other), what
-- is put back on leaving, fullscreen and enabled=no ending it, the
-- property, and the controls inside: play/pause, the way back and the
-- timeline, nothing else.
local T = require "lib"

local W, H = 1280, 720

-- props: the window as it is before entering.
local function start(props, script_opts)
    T.unload()
    props = props or {}
    props["mpv-version"] = "mpv v0.40.0"
    props["osd-dimensions"] = { w = W, h = H }
    if props.ontop == nil then props.ontop = false end
    if props.border == nil then props.border = true end
    if props.fullscreen == nil then props.fullscreen = false end
    if props.geometry == nil then props.geometry = "" end -- mpv's default
    mp = T.fake_mp(props)
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = W, h = H })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.fire("fullscreen", props.fullscreen)
    mp.mouse(0, 0)
    mp.advance(1)
    -- What is written to the window, in order: "name=value" and the
    -- commands for mpv.net, "mpvnet ...".
    mp.window = {}
    local set_bool, set = mp.set_property_bool, mp.set_property
    mp.set_property_bool = function(name, v)
        if name ~= "input-builtin-dragging" and name ~= "osc" and name ~= "pause" then
            mp.window[#mp.window + 1] = name .. "=" .. tostring(v)
        end
        return set_bool(name, v)
    end
    mp.set_property = function(name, v)
        mp.window[#mp.window + 1] = name .. "=" .. tostring(v)
        return set(name, v)
    end
    local commandv = mp.commandv
    mp.commandv = function(...)
        local c = { ... }
        if c[1] == "script-message-to" and c[2] == "mpvnet" then
            mp.window[#mp.window + 1] = "mpvnet " .. table.concat(c, " ", 3)
        end
        return commandv(...)
    end
    return mp
end

local function pip() return package.loaded["core.pip"] end
local function key() mp.bindings.pip.fn() end
local function writes() local s = table.concat(mp.window, ", "); mp.window = {}; return s end
local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function last_cmd() local c = mp.commands[#mp.commands]; return c and table.concat(c, " ") end
-- mpv.net: it takes every message sent to it.
local function mpvnet(...)
    local c = { ... }
    if c[1] == "script-message-to" and c[2] == "mpvnet" then return true end
end
-- The window resized to w x h (mpv does it after the writes).
local function resize(w, h)
    mp.props["osd-dimensions"] = { w = w, h = h }
    mp.fire("osd-dimensions", { w = w, h = h })
    mp.advance(0.5)
end

-- The binding and the property --------------------------------------------------------
start({ ["current-window-scale"] = 1 })
T.check(mp.bindings.pip ~= nil, "a named binding: script-binding suji/pip")
T.eq(mp.bindings.pip.key, nil, "with no key of its own")
T.eq(mp.props[pip().PROP], false, "user-data/suji/pip is false at start")
T.eq(pip().PROP, "user-data/suji/pip", "under that name")

-- mpv: geometry in, centred, the user's geometry and the old scale out -----------------
local DELAY = 0.3
start({ ["current-window-scale"] = 1.5 })
key()
T.eq(pip().active(), true, "the key enters")
T.eq(mp.props["user-data/suji/pip"], true, "the property turns true")
T.eq(writes(), "ontop=true, border=false", "mpv: on top and no border first")
T.eq(pip().PLACE_DELAY, DELAY, "the geometry after " .. DELAY .. " s")
mp.advance(DELAY - 0.01)
T.eq(writes(), "", "not yet")
mp.advance(0.02)
T.eq(writes(), "geometry=25%-24-72", "then the corner, on its own")
T.eq(mp.active_timers(), 0, "and no timer left")
key()
T.eq(pip().active(), false, "the key again leaves")
T.eq(mp.props["user-data/suji/pip"], false, "the property turns false")
T.eq(writes(), "geometry=+50%+50%, current-window-scale=1.500, geometry=, border=true, ontop=false",
    "mpv: centred first, then the old scale, the user's geometry (none), the border and on top")
mp.advance(1)
T.eq(mp.active_timers(), 0, "no timers")

-- The user's own geometry comes back: mpv applies it to every new file
start({ ["current-window-scale"] = 1, geometry = "50%" })
key()
mp.advance(1)
writes()
key()
T.eq(writes(), "geometry=+50%+50%, current-window-scale=1.000, geometry=50%, border=true, ontop=false",
    "the user's geometry back, after centring and the scale")
T.eq(mp.props.geometry, "50%", "and it stays")

-- Left before the geometry came: it never comes
start({ ["current-window-scale"] = 1 })
key()
mp.advance(0.1)
key()
writes()
mp.advance(1)
T.eq(writes(), "", "left within the delay: no geometry after")
T.eq(mp.active_timers(), 0, "no timers")

-- Fullscreen before: off first, back on last; the geometry once it is off
start({ ["current-window-scale"] = 0.75, fullscreen = true, ontop = true })
key()
T.eq(writes(), "fullscreen=false, ontop=true, border=false", "fullscreen: turned off first")
T.eq(pip().active(), true, "and turning it off does not end picture in picture")
mp.advance(1)
T.eq(writes(), "geometry=25%-24-72", "then the corner")
-- mpv tells late that fullscreen is off (macOS animates it): placed again.
mp.fire("fullscreen", false)
mp.advance(DELAY / 2)
mp.fire("fullscreen", false)
mp.advance(DELAY - 0.01)
T.eq(writes(), "", "fullscreen off seen again: the delay starts over")
mp.advance(0.02)
T.eq(writes(), "geometry=25%-24-72", "and the corner again, once")
T.eq(mp.active_timers(), 0, "no timer left")
key()
T.eq(writes(), "geometry=+50%+50%, current-window-scale=0.750, geometry=, border=true, ontop=true, fullscreen=true",
    "fullscreen again, last")
T.eq(pip().active(), false, "and that does not end it twice")
T.eq(mp.props["user-data/suji/pip"], false, "property false")
mp.fire("fullscreen", false)
mp.advance(1)
T.eq(writes(), "", "outside, fullscreen off places nothing")

-- Maximized: unmaximized first, maximized again after
start({ ["current-window-scale"] = 1, ["window-maximized"] = true })
key()
T.eq(writes(), "window-maximized=false, ontop=true, border=false", "maximized: unmaximized first")
mp.advance(1)
writes()
key()
T.eq(writes(), "geometry=+50%+50%, current-window-scale=1.000, geometry=, border=true, ontop=false, window-maximized=true",
    "and maximized again")
start({ ["current-window-scale"] = 1, ["window-maximized"] = false })
key()
mp.advance(1)
key()
T.check(not writes():find("maximized", 1, true), "not maximized: left alone")

-- A scale that is no number is not written back
for _, bad in ipairs({ 0, -1, 0 / 0, 1 / 0 }) do
    start({ ["current-window-scale"] = bad })
    key()
    mp.advance(1)
    writes()
    key()
    T.eq(writes(), "geometry=+50%+50%, geometry=, border=true, ontop=false", "no scale written for " .. tostring(bad))
end

-- mpv.net: its own commands ---------------------------------------------------------
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280 })
mp.on_command = mpvnet
key()
T.eq(writes(), "ontop=true, border=false, mpvnet window-scale 0.375, mpvnet move-window right, mpvnet move-window bottom",
    "mpv.net: a quarter of the screen, docked bottom right")
resize(480, 270)
key()
T.eq(writes(), "mpvnet window-scale 1.000, border=true, ontop=false", "back to the width it had: not centred")
T.eq(mp.props["user-data/suji/pip"], false, "property false")

-- The width it had, not the window-scale property (mpv.net says 1)
start({ ["display-width"] = 1920, ["video-params/dw"] = 1920, ["window-scale"] = 1 })
mp.on_command = mpvnet
key()
T.eq(writes(), "ontop=true, border=false, mpvnet window-scale 0.250, mpvnet move-window right, mpvnet move-window bottom",
    "mpv.net: the factor from the screen and the video")
key()
T.eq(writes(), "mpvnet window-scale 0.667, border=true, ontop=false", "1280 of 1920: 0.667")

-- No display-width or no video width: 0.25
for i, p in ipairs({ { ["video-params/dw"] = 1280 }, { ["display-width"] = 1920 }, { ["display-width"] = 1920, ["video-params/dw"] = 0 } }) do
    start(p)
    mp.on_command = mpvnet
    key()
    T.check(writes():find("mpvnet window-scale 0.250", 1, true) ~= nil, "mpv.net: 0.25 when the sizes are unknown " .. i)
    key()
    if i == 1 then
        T.check(writes():find("mpvnet window-scale 1.000", 1, true) ~= nil, "with the video width, its size back")
    else
        T.check(not writes():find("window-scale", 1, true), "no size to give back without the video width " .. i)
    end
end

-- mpv.net from fullscreen: the width then is the screen's, no size to give back
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280, fullscreen = true })
mp.props["osd-dimensions"] = { w = 1920, h = 1080 }
mp.on_command = mpvnet
key()
T.eq(writes(), "fullscreen=false, ontop=true, border=false, mpvnet window-scale 0.375, mpvnet move-window right, mpvnet move-window bottom",
    "mpv.net: fullscreen off first")
mp.advance(1)
T.eq(writes(), "", "no geometry for mpv.net")
key()
T.eq(writes(), "border=true, ontop=false, fullscreen=true", "no resize, fullscreen back on last")

-- mpv.net from a maximized window: the same, no size to give back
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280, ["window-maximized"] = true })
mp.props["osd-dimensions"] = { w = 1920, h = 1080 }
mp.on_command = mpvnet
key()
T.eq(writes(), "window-maximized=false, ontop=true, border=false, mpvnet window-scale 0.375, mpvnet move-window right, mpvnet move-window bottom",
    "mpv.net: unmaximized first")
key()
T.eq(writes(), "border=true, ontop=false, window-maximized=true", "no resize, maximized again")

-- The window settling (macOS animates leaving fullscreen): the geometry
-- waits for the last change of size, and is written once ---------------------------
local function size(w, h) mp.fire("osd-dimensions", { w = w, h = h }) end
start({ ["current-window-scale"] = 1, fullscreen = true })
key()
writes()
for i = 1, 8 do -- a change every 0.2 s for 1.6 s
    mp.advance(0.2)
    size(1920 - i * 100, 1080 - i * 50)
end
T.eq(writes(), "", "nothing while the window keeps changing")
mp.advance(DELAY - 0.01)
T.eq(writes(), "", "nor right after the last change")
mp.advance(0.02)
T.eq(writes(), "geometry=25%-24-72", "then the corner, once, " .. DELAY .. " s after the last change")
size(320, 180) -- the change the geometry itself causes
mp.advance(1)
T.eq(writes(), "", "the change it causes writes nothing more")
T.eq(mp.active_timers(), 0, "no timers")
-- A window that never stops changing: placed at PLACE_MAX all the same
start({ ["current-window-scale"] = 1, fullscreen = true })
T.eq(pip().PLACE_MAX, 3, "at most 3 s")
local t0 = mp.now
key()
writes()
local at
for i = 1, 50 do
    mp.advance(0.1)
    if not at and #mp.window > 0 then at = mp.now - t0 end
    size(1000 + i, 600 + i)
end
T.check(at and at > 2.9 and at < 3.15, "written at 3 s: " .. tostring(at))
T.eq(writes(), "geometry=25%-24-72", "once, though it kept changing")
mp.advance(1) -- the last paint
T.eq(writes(), "", "and nothing after")
T.eq(mp.active_timers(), 0, "no timers")
-- From a window: no change, 0.3 s as before; a change before it waits
start({ ["current-window-scale"] = 1 })
key()
writes()
mp.advance(0.2)
size(1279, 719)
mp.advance(0.2)
T.eq(writes(), "", "a change of size: it waits")
mp.advance(0.11)
T.eq(writes(), "geometry=25%-24-72", "0.3 s after that change")
-- Leaving while it waits cancels it
start({ ["current-window-scale"] = 1, fullscreen = true })
key()
size(1500, 900)
key()
writes()
size(1400, 800)
mp.advance(5)
T.eq(writes(), "", "left while waiting: never placed")
T.eq(mp.active_timers(), 0, "no timers")

-- Any other: on top and no border only --------------------------------------------
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280 })
key()
T.eq(writes(), "ontop=true, border=false, mpvnet window-scale 0.375", "not mpv.net: the first command fails, no more")
T.eq(pip().active(), true, "still picture in picture")
key()
T.eq(writes(), "border=true, ontop=false", "and only those two back")

-- Fullscreen turned on in picture in picture ends it, in place -----------------------
start({ ["current-window-scale"] = 1 })
key()
mp.advance(1)
writes()
mp.set_property_bool("fullscreen", true) -- a double click, or a key
T.eq(pip().active(), false, "fullscreen on: picture in picture ends")
T.eq(writes(), "fullscreen=true, geometry=, border=true, ontop=false",
    "the user's geometry, border and on top back, no resize")
mp.advance(1)
T.eq(writes(), "", "and nothing after")
start({ ["current-window-scale"] = 1, geometry = "50%" })
key()
mp.advance(1)
writes()
mp.set_property_bool("fullscreen", true)
T.eq(writes(), "fullscreen=true, geometry=50%, border=true, ontop=false", "a geometry of the user's comes back")
start({ ["current-window-scale"] = 1 })
key()
writes()
mp.set_property_bool("fullscreen", true) -- before the window was placed
mp.advance(1)
T.eq(writes(), "fullscreen=true, geometry=, border=true, ontop=false", "fullscreen before the placing: never placed")
T.eq(mp.active_timers(), 0, "no timers")
T.eq(mp.props.fullscreen, true, "and it stays fullscreen")
T.eq(mp.props["user-data/suji/pip"], false, "property false")
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280 })
mp.on_command = mpvnet
key()
writes()
mp.set_property_bool("fullscreen", true)
T.eq(writes(), "fullscreen=true, border=true, ontop=false", "mpv.net too: no resize")

-- enabled=no leaves it, in full; the key does nothing while off ----------------------
start({ ["current-window-scale"] = 2, fullscreen = true })
key()
writes()
mp.set_opts({ enabled = false })
T.eq(pip().active(), false, "enabled=no leaves picture in picture")
T.eq(writes(), "geometry=+50%+50%, current-window-scale=2.000, geometry=, border=true, ontop=false, fullscreen=true",
    "with everything back")
key()
T.eq(pip().active(), false, "the key does nothing while suji is off")
T.eq(writes(), "", "and writes nothing")
mp.set_opts({ enabled = true })
key()
T.eq(pip().active(), true, "on again: the key works")

-- A new file keeps it
start({ ["current-window-scale"] = 1 })
key()
writes()
mp.emit("end-file")
mp.emit("file-loaded")
T.eq(pip().active(), true, "a new file keeps picture in picture")
T.eq(writes(), "", "and the window is left alone")

-- Quitting leaves it first (mpv.net would remember the small window), then
-- deletes the property
mp.emit("shutdown")
T.eq(pip().active(), false, "quitting leaves picture in picture")
T.eq(writes(), "geometry=+50%+50%, current-window-scale=1.000, geometry=, border=true, ontop=false",
    "with everything back")
T.eq(mp.props["user-data/suji/pip"], nil, "deleted when mpv quits")
mp.advance(1)
T.eq(mp.active_timers(), 0, "no timers")
start({ ["display-width"] = 1920, ["video-params/dw"] = 1280 })
mp.on_command = mpvnet
key()
writes()
mp.emit("shutdown")
T.eq(writes(), "mpvnet window-scale 1.000, border=true, ontop=false", "mpv.net: its size back before quitting")

-- A listener that fails does not stop the way back
start({ ["current-window-scale"] = 1 })
pip().on_change(function() error("boom") end)
key()
T.eq(pip().active(), true, "entered all the same")
key()
T.eq(pip().active(), false, "and left")
local errors = 0
for _, l in ipairs(mp.logs) do if l[1] == "error" and tostring(l[2]):find("picture in picture: ", 1, true) then errors = errors + 1 end end
T.eq(errors, 2, "each failure logged")

-- The controls inside -------------------------------------------------------------------
local function boxes()
    local t = {}
    for _, b in ipairs(package.loaded["core.layout"].current().boxes) do
        t[#t + 1] = package.loaded["core.modules"].name_of(b.mod)
    end
    return table.concat(t, ",")
end
local icon = function(...) return package.loaded["core.modules"].ctx.icon(...) end

start({ ["current-window-scale"] = 1, ["media-title"] = "Movie" })
mp.fire("media-title", "Movie")
mp.fire("volume", 100)
mp.fire("pause", true) -- all shown
mp.advance(1)
T.check(painted():find("}Movie", 1, true) ~= nil, "before: the title")
T.check(painted():find(icon("pip", 1186, 680, 1), 1, true) ~= nil, "the button in the row, before fullscreen")
T.eq(boxes(), "pause,volume,time,subtitles,speed,more,pip,fullscreen", "the default row")
mp.mouse(1186, 680)
mp.button("press")
T.eq(pip().active(), true, "a click on the row's button enters")
resize(320, 180)
T.eq(boxes(), "pip,pause", "inside: only the way back and play/pause")
local placed = package.loaded["core.layout"].current()
local back, centre = placed.boxes[1], placed.boxes[2]
T.eq(back.x1, 316, "the way back 4 px from the right edge")
T.eq(back.y0, 4, "and from the top")
T.eq((centre.x0 + centre.x1) / 2, 160, "play/pause in the middle")
T.eq(centre.cy, 90, "in both directions")
T.eq(placed.bar.y0, 152, "the timeline's zone low: from 152")
T.eq(placed.bar.y1, 176, "to 176")
T.eq(mp.props["user-data/suji/margins"].bottom, 28, "margins follow it")
mp.mouse(200, 120)
mp.advance(5)
local p = painted()
T.check(p:find(icon("pip_exit", 294, 26, 1), 1, true) ~= nil, "the way back drawn at the top right")
T.check(p:find(icon("play", 160, 90, 1), 1, true) ~= nil, "play drawn in the middle")
T.check(not p:find("}Movie", 1, true), "no title")
T.check(not p:find("01:40", 1, true), "no time")
local _, strokes = p:gsub("\\3c&HFFFFFF&\\3a&H00&\\p3}", "")
T.eq(strokes, 2, "no row: two icons drawn, no more")
-- The grown line, 5 px, its bottom 14 px over the bottom edge: from 161 to 166, *4 in \p3.
T.check(p:find("\\1a&HA6&\\p3}m 0 644 l 1280 644 l 1280 664 l 0 664", 1, true) ~= nil, "the timeline, grown, low")
T.eq(mp.active_timers(), 0, "no timers at rest inside")

-- Clicks: play/pause, the timeline, the way back
mp.mouse(160, 90)
mp.commands = {}
mp.button("press")
T.eq(last_cmd(), "cycle pause", "the middle button plays and pauses")
mp.mouse(80, 164)
mp.commands = {}
mp.button("down")
T.eq(last_cmd(), "seek 25.000 absolute+exact", "the timeline seeks")
mp.button("up")
mp.mouse(150, 30)
T.eq(mp.bindings["suji-bar"], nil, "elsewhere nothing is bound: mpv drags the window")
mp.advance(1)
mp.mouse(294, 26)
mp.button("press")
T.eq(pip().active(), false, "the way back leaves")
resize(W, H)
T.eq(boxes(), "pause,volume,time,subtitles,speed,more,pip,fullscreen", "the row is back")
mp.mouse(640, 680)
mp.advance(1)
T.check(painted():find("}Movie", 1, true) ~= nil, "and the title")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers at rest after")

-- Not paused: the mouse anywhere in the window brings the controls up,
-- the way back at the top too; still, they hide
start({ ["current-window-scale"] = 1 })
key()
resize(480, 270)
mp.mouse(240, 20) -- the top, far from the timeline: not on a button
mp.advance(0.5)
T.check(painted():find(icon("pip_exit", 454, 26, 1), 1, true) ~= nil, "the way back shown in full at the top")
T.eq(mp.bindings["suji-bar"], nil, "nothing bound there: mpv drags the window")
mp.advance(5)
T.check(not painted():find(icon("pip_exit", 454, 26, 1), 1, true), "still: hidden again")
T.eq(mp.active_timers(), 0, "no timers at rest")
mp.mouse(241, 20)
mp.advance(0.5)
T.check(painted():find(icon("pip_exit", 454, 26, 1), 1, true) ~= nil, "moved again: shown")
mp.mouse(240, 20, false) -- out of the window
mp.advance(1)
T.check(not painted():find(icon("pip_exit", 454, 26, 1), 1, true), "out of the window: hidden")

-- A double click on the row's button enters once
start({ ["current-window-scale"] = 1 })
mp.fire("pause", true)
mp.advance(1)
mp.mouse(1186, 680)
mp.button("press")
mp.button("press")
T.eq(pip().active(), true, "a double click enters once")

-- With pause and pip out of the row, inside they are there all the same
start({ ["current-window-scale"] = 1 }, { controls = "time,space,fullscreen" })
key()
resize(320, 180)
T.eq(boxes(), "pip,pause", "whatever the controls option")

-- Entering closes a menu; no menu opens inside; no thumbnail; action buttons wait ------
start({ ["current-window-scale"] = 1 })
mp.fire("pause", true)
mp.advance(1)
local menu = package.loaded["core.menu"]
mp.send("open-menu", T.json({ type = "x", items = { { title = "One", value = "quit" } } }))
mp.advance(1)
T.eq(menu.is_open(), true, "a menu open")
key()
mp.advance(1)
T.eq(menu.is_open(), false, "entering closes it")
mp.send("open-menu", T.json({ type = "x", items = { { title = "One", value = "quit" } } }))
mp.advance(1)
T.eq(menu.is_open(), false, "open-menu does nothing inside")
resize(320, 180)
mp.send("thumbfast-info", T.json({ width = 200, height = 112, disabled = false, available = true }))
mp.commands = {}
mp.mouse(80, 164)
mp.advance(1)
local thumbs = 0
for _, c in ipairs(mp.commands) do if c[2] == "thumbfast" then thumbs = thumbs + 1 end end
T.eq(thumbs, 0, "no thumbnail asked for on the timeline")
mp.send("show-action", "skip", T.json({ text = "Skip opening", command = { "script-message-to", "fake", "skip" } }))
mp.advance(1)
T.check(not painted():find("}Skip opening", 1, true), "an action button is not drawn inside")
mp.mouse(250, 140)
mp.advance(0.1)
T.eq(mp.bindings["suji-bar"], nil, "nor clickable where it would be")
key()
resize(W, H)
mp.advance(1)
T.check(painted():find("}Skip opening", 1, true) ~= nil, "it shows when the window comes back")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers at rest")

T.done("test_pip")
