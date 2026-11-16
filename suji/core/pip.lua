-- Picture in picture: the window becomes small, borderless and always on
-- top, in the bottom right corner of the screen, and the controls become
-- three (core/layout.lua): play/pause in the middle, the way back at the
-- top right and the timeline. Entering saves what it changes; leaving
-- puts it back.
--
-- How the window is moved and resized depends on who embeds mpv, chosen
-- when entering:
--   mpv      current-window-scale is there: geometry puts the window in
--            the corner, and on leaving it is centred (mpv cannot tell
--            where it was) and given its old scale back.
--   mpvnet   mpv.net ignores geometry at run time and has no
--            current-window-scale, but takes its own commands,
--            script-message-to mpvnet window-scale and move-window. On
--            leaving the window gets its size back, docked in the corner
--            of its monitor (move-window center would jump to the primary
--            one).
--   other    anything else: only on top and without borders, the size
--            is left alone.
-- Turning fullscreen on while in picture in picture ends it, with no
-- resize: border and on top come back, the window stays fullscreen
-- (main.lua calls leave(false)).

local msg = require "mp.msg"
local state = require "core.state"

local M = {}

M.PROP = "user-data/suji/pip" -- true while in picture in picture (docs/api.md)

-- For mpv: a quarter of the screen's width, 24 px from the right edge and
-- 72 px from the bottom, room for a taskbar or a dock. Back: centred.
local GEOMETRY, CENTRE = "25%-24-72", "+50%+50%"
local WIDTH = 0.25 -- of the screen, for mpv.net

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

local function set_bool(name, v)
    if type(v) == "boolean" then mp.set_property_bool(name, v) end
end

local function changed(on)
    state.pip = on
    mp.set_property_native(M.PROP, on)
    if listener then listener() end
end

function M.enter()
    if saved then return end
    local s = { ontop = mp.get_property_bool("ontop"), border = mp.get_property_bool("border"),
                fullscreen = mp.get_property_bool("fullscreen"), backend = "other" }
    local scale = mp.get_property_number("current-window-scale")
    saved = s -- before the writes: fullscreen=no below must not end it
    -- mpv: geometry goes first. On X11 it is lost when it comes after
    -- border=no, or after fullscreen=no (leaving fullscreen puts the old
    -- size back); before them, the window keeps it.
    if scale then
        s.backend, s.scale = "mpv", scale
        mp.set_property("geometry", GEOMETRY)
    end
    if s.fullscreen then mp.set_property_bool("fullscreen", false) end
    mp.set_property_bool("ontop", true)
    mp.set_property_bool("border", false)
    if not scale then
        local dim = mp.get_property_native("osd-dimensions")
        local dw = mp.get_property_number("video-params/dw")
        s.width = type(dim) == "table" and tonumber(dim.w) or nil
        s.dw = dw
        local f = factor((mp.get_property_number("display-width") or 0) * WIDTH / (dw or 0)) or factor(WIDTH)
        if mpvnet("window-scale", f) then
            s.backend = "mpvnet"
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
    if resize ~= false then
        if s.backend == "mpv" then
            mp.set_property("geometry", CENTRE)
            local f = factor(s.scale)
            if f then mp.set_property("current-window-scale", f) end
        elseif s.backend == "mpvnet" then
            local f = factor(s.width and s.dw and s.width / s.dw)
            if f then mpvnet("window-scale", f) end
        end
    end
    set_bool("border", s.border)
    set_bool("ontop", s.ontop)
    if resize ~= false and s.fullscreen then mp.set_property_bool("fullscreen", true) end
    changed(false)
end

function M.toggle()
    if saved then M.leave() else M.enter() end
end

return M
