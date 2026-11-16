-- Picture in picture: the window becomes small, borderless and always on
-- top, in the bottom right corner of the screen, and the controls become
-- three (core/layout.lua): play/pause in the middle, the way back at the
-- top right and the timeline. Entering saves what it changes; leaving
-- puts it back.
--
-- How the window is moved and resized depends on who embeds mpv, chosen
-- when entering:
--   mpv      current-window-scale is there: geometry puts the window in
--            the corner (see place below). On leaving the window goes
--            where mpv would open it, with its old scale: mpv cannot
--            tell where it was.
--   mpvnet   mpv.net ignores geometry at run time and has no
--            current-window-scale, but takes the window-scale property
--            and its own command script-message-to mpvnet move-window,
--            the first of which tells it is mpv.net (its window-scale
--            command would also write the factor on screen). On
--            leaving the window gets its size back, docked in the corner
--            of its monitor (move-window center would jump to the primary
--            one). Entered from fullscreen, there is no size to give back:
--            the window is fullscreen again anyway.
--   other    anything else: only on top and without borders, the size
--            is left alone.
-- A maximized window is unmaximized first, and maximized again after.
-- Turning fullscreen on while in picture in picture ends it, with no
-- resize: border and on top come back, the window stays fullscreen
-- (main.lua calls fullscreen()).

local msg = require "mp.msg"
local draw = require "core.draw"
local state = require "core.state"

local M = {}

M.PROP = "user-data/suji/pip" -- true while in picture in picture (docs/api.md)

-- For mpv: a quarter of the screen's width, 24 px from the right edge and
-- 72 px from the bottom, room for a taskbar or a dock. Back: centred.
local GEOMETRY, CENTRE = "25%-24-72", "+50%+50%"
local WIDTH = 0.25 -- of the screen, for mpv.net
-- Seconds from border=no (or the end of fullscreen) to geometry, see place.
M.PLACE_DELAY = 0.3
M.PLACE_MAX = 3 -- seconds: written by then even if the window keeps changing

local saved -- nil outside picture in picture: what entering changed
local listener

function M.active() return saved ~= nil end

-- fn() runs after entering or leaving.
function M.on_change(fn) listener = fn end

-- A scale factor as mpv takes it, or nil when f is no usable number.
local function factor(f)
    if type(f) ~= "number" or not (f > 0 and f < math.huge) then return nil end
    return ("%.3f"):format(f)
end

-- true when mpv.net took the command (on mpv: nil, no such client).
local function mpvnet(...)
    return mp.commandv("script-message-to", "mpvnet", ...) == true
end

-- mpv.net: the window-scale property set to f (a factor, see factor).
-- Kept in what mpv takes, so an odd video still resizes the window. The
-- value it already has (1 at start, whatever the size) would tell nobody:
-- 0.001 more then (less at the top of the range).
local SCALE_MIN, SCALE_MAX = 0.01, 100
local function set_scale(f)
    local n = math.max(SCALE_MIN, math.min(SCALE_MAX, tonumber(f)))
    local now = mp.get_property_number("window-scale")
    if now and math.abs(now - n) < 0.0005 then n = n + (n + 0.001 <= SCALE_MAX and 0.001 or -0.001) end
    mp.set_property_number("window-scale", n)
end

local function set_bool(name, v)
    if type(v) == "boolean" then mp.set_property_bool(name, v) end
end

local function changed(on)
    state.pip = on
    mp.set_property_native(M.PROP, on)
    -- The way back must keep working whatever the listener does.
    if listener then
        local ok, err = pcall(listener)
        if not ok then msg.error("picture in picture: " .. draw.printable(err, 300)) end
    end
end

-- mpv: geometry goes on its own, once the window has settled. On macOS a
-- border taken away after the window was placed centres it again, so it
-- has to come after; on X11, written right after border=no, without
-- giving mpv a turn, it is lost. And leaving fullscreen on macOS is
-- animated: fullscreen turns false at once, the window keeps changing
-- size for a while and is centred at the end. So while a placing is
-- pending, every change of the window's size (resized) starts the wait
-- over: geometry is written PLACE_DELAY after the last change, or at
-- PLACE_MAX from the start if it never stops. With no change (a window,
-- not fullscreen) that is PLACE_DELAY after border=no. Writing it ends
-- the pending placing, so the resize it causes itself starts nothing.
-- fullscreen(false) inside starts a new one (the same geometry written
-- again does move the window back).
-- Leaving waits the same way to put the user's force-window-position back
-- (see enter): mpv takes the geometries written on leaving once the
-- window moves, and with the user's "no" already there mpv 0.42 would not
-- move it. Entering again before that keeps the user's value, still to
-- put back. One shot, only while entering, leaving or leaving fullscreen
-- inside: no timer at rest.
local pending -- mp.get_time() by which the timer fires anyway, nil: none
local restore_force -- the user's force-window-position, to put back after leaving

local place_timer = mp.add_timeout(M.PLACE_DELAY, function()
    pending = nil
    if saved then
        if saved.backend == "mpv" then mp.set_property("geometry", GEOMETRY) end
    elseif restore_force then
        local v = restore_force
        restore_force = nil
        mp.set_property("force-window-position", v)
    end
end, true)

-- Wait PLACE_DELAY again, but not past the deadline.
local function wait()
    place_timer:kill()
    place_timer.timeout = math.max(0, math.min(M.PLACE_DELAY, pending - mp.get_time()))
    place_timer:resume()
end

local function place()
    if not pending then pending = mp.get_time() + M.PLACE_MAX end
    wait()
end

-- Stop waiting: whatever was pending is dropped.
local function cancel()
    place_timer:kill()
    pending = nil
end

-- The window's size changed (osd-dimensions): a pending placing waits more.
function M.resized()
    if pending then wait() end
end

function M.enter()
    if saved then return end
    local s = { ontop = mp.get_property_bool("ontop"), border = mp.get_property_bool("border"),
                fullscreen = mp.get_property_bool("fullscreen"),
                maximized = mp.get_property_bool("window-maximized"), backend = "other" }
    local scale = mp.get_property_number("current-window-scale")
    -- Back in before the user's force-window-position was put back: that
    -- one is still theirs, what is there now is ours.
    local force = restore_force
    restore_force = nil
    cancel()
    saved = s -- before the writes: fullscreen=no below must not end it
    if s.fullscreen then mp.set_property_bool("fullscreen", false) end
    if s.maximized then mp.set_property_bool("window-maximized", false) end
    mp.set_property_bool("ontop", true)
    mp.set_property_bool("border", false)
    if scale then
        -- The user's own geometry (from mpv.conf, say), to put back.
        s.backend, s.scale, s.geometry = "mpv", scale, mp.get_property("geometry")
        -- Since mpv 0.42 geometry only moves a window that exists with
        -- force-window-position=yes (before, it always did). Kept while
        -- inside, for the placing again after fullscreen and new files,
        -- and put back once the window has settled after leaving.
        s.force = force or mp.get_property("force-window-position")
        mp.set_property("force-window-position", "yes")
        place()
    else
        if force then mp.set_property("force-window-position", force) end
        local dim = mp.get_property_native("osd-dimensions")
        local dw = mp.get_property_number("video-params/dw")
        -- Fullscreen or maximized, the width read here is still the big
        -- one (the window has not come down yet): not the one to give back.
        if not s.fullscreen and not s.maximized then s.width = type(dim) == "table" and tonumber(dim.w) or nil end
        s.dw = dw
        local f = factor((mp.get_property_number("display-width") or 0) * WIDTH / (dw or 0)) or factor(WIDTH)
        if mpvnet("move-window", "right") then
            s.backend = "mpvnet"
            set_scale(f)
            -- Again, now that it is small: docked in the corner.
            mpvnet("move-window", "right")
            mpvnet("move-window", "bottom")
        end
    end
    msg.debug("picture in picture: " .. s.backend)
    changed(true)
end

-- resize = false keeps the window's size and place (fullscreen came on).
function M.leave(resize)
    local s = saved
    if not s then return end
    saved = nil -- before the writes: fullscreen=yes below must not end it twice
    cancel()
    if resize == false then
        -- The window stays as it is, but the user's geometry comes back:
        -- mpv applies it to every new file, and ours would send the window
        -- to the corner each time.
        if s.backend == "mpv" and type(s.geometry) == "string" then mp.set_property("geometry", s.geometry) end
    else
        if s.backend == "mpv" then
            -- Centred and at its old scale first: the user's geometry
            -- alone (none, by default) would leave the window in the
            -- corner. Then the user's, which mpv applies again to every
            -- new file; on X11 a place in it (+100+100) only holds when
            -- it comes after the scale.
            mp.set_property("geometry", CENTRE)
            local f = factor(s.scale)
            if f then mp.set_property("current-window-scale", f) end
            if type(s.geometry) == "string" then mp.set_property("geometry", s.geometry) end
        elseif s.backend == "mpvnet" then
            local f = factor(s.width and s.dw and s.width / s.dw)
            if f then set_scale(f) end
        end
    end
    if s.backend == "mpv" and type(s.force) == "string" then
        restore_force = s.force -- once the window has settled (see place_timer)
        place()
    end
    set_bool("border", s.border)
    set_bool("ontop", s.ontop)
    if resize ~= false then
        if s.maximized then mp.set_property_bool("window-maximized", true) end
        if s.fullscreen then mp.set_property_bool("fullscreen", true) end
    end
    changed(false)
end

-- mpv quits: leave, and the user's force-window-position at once.
function M.quit()
    M.leave()
    if restore_force then
        cancel()
        local v = restore_force
        restore_force = nil
        mp.set_property("force-window-position", v)
    end
end

function M.toggle()
    if saved then M.leave() else M.enter() end
end

-- The fullscreen property changed: on ends picture in picture where the
-- window is; off, while in it, places the window again (see place).
function M.fullscreen(on)
    if on then M.leave(false)
    elseif saved and saved.backend == "mpv" then place() end
end

return M
