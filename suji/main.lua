-- suji: a minimal on-screen controller for mpv.
-- Entry point: version check, property observers and the frame renderer.

local msg = require "mp.msg"
local opts = require "options"
local state = require "state"
local draw = require "draw"
local animation = require "animation"
local painter = require "painter"
local mouse = require "mouse"
local bar = require "elements.bar"

local MIN_MAJOR, MIN_MINOR = 0, 39

local function check_version()
    local v = mp.get_property("mpv-version", "")
    local major, minor = v:match("(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    if major and (major < MIN_MAJOR or (major == MIN_MAJOR and minor < MIN_MINOR)) then
        msg.warn(("suji needs mpv %d.%d or newer, this is %s"):format(MIN_MAJOR, MIN_MINOR, v))
    end
end

local function debug_sizes(reason)
    if not opts.debug then return end
    msg.info(("%s: osd-dimensions %dx%d, display-hidpi-scale %s, scale option %s, scale %.3f")
        :format(reason, state.w, state.h, tostring(mp.get_property_number("display-hidpi-scale")),
            tostring(opts.scale), state.scale))
end

-- Repaint only when the end of the progress line moves by a whole pixel.
local function update_progress()
    state.set("progress_px", bar.progress_px(state.time, state.duration, state.w))
end

local function request_if_dirty()
    if state.dirty then painter.request() end
end

-- Visibility changes are smoothed by a short clock-based transition.
local tween = animation.new(0.15)

painter.set_renderer(function()
    if state.w <= 0 or state.h <= 0 then return "", false end
    local now = mp.get_time()
    animation.set_target(tween, mouse.target(now), now)
    local v = animation.value(tween, now)
    return bar.render(state, v, opts, bar.drag_time()), animation.running(tween, now)
end)

check_version()

mp.observe_property("osd-dimensions", "native", function(_, dim)
    local w, h = 0, 0
    if type(dim) == "table" then w, h = tonumber(dim.w) or 0, tonumber(dim.h) or 0 end
    local changed = state.set("w", w)
    changed = state.set("h", h) or changed
    if not changed then return end
    bar.release() -- the grid changed under a drag in progress
    update_progress()
    debug_sizes("resize")
    mouse.on_resize()
end)

mp.observe_property("display-hidpi-scale", "number", function(_, scale)
    state.set("hidpi", scale or 1)
    state.set("scale", draw.scale(state.hidpi, opts.scale))
    debug_sizes("hidpi")
    mouse.on_resize()
end)

mp.observe_property("time-pos", "number", function(_, t)
    state.time = t
    update_progress()
    request_if_dirty()
end)

mp.observe_property("duration", "number", function(_, d)
    if state.set("duration", d) then
        bar.release(false) -- a new file, or the length is unknown again
        update_progress()
    end
    mouse.refresh()
end)

mp.observe_property("pause", "bool", function(_, paused)
    state.set("paused", paused == true)
    mouse.refresh()
end)

mp.observe_property("display-fps", "number", function(_, fps)
    painter.set_fps(fps)
end)

mp.observe_property("mouse-pos", "native", mouse.on_mouse_pos)

state.scale = draw.scale(state.hidpi, opts.scale)
debug_sizes("start")
