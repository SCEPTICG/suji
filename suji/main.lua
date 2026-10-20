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
local controls = require "elements.controls"

local MIN_MAJOR, MIN_MINOR = 0, 39
local MAX_TITLE = 200 -- characters kept from a title (at most 4 bytes each)

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
        :format(reason, math.floor(state.w), math.floor(state.h), tostring(mp.get_property_number("display-hidpi-scale")),
            tostring(opts.scale), state.scale))
end

-- Visibility changes are smoothed by a short clock-based transition.
local tween = animation.new(0.15)

-- The controls, title and grown bar are on screen (visibility above 0).
local function grown()
    local now = mp.get_time()
    return animation.value(tween, now) > 0 or animation.running(tween, now)
end

-- Something is on screen: the rest line, or a bar that has not faded out.
local function bar_shown()
    return opts.idle_line or grown()
end

-- Repaint only when the end of the progress line moves by a whole pixel
-- and the line is on screen, or when the time shown or the end of the
-- cached range changes while the controls are on screen.
local function update_progress()
    local px = bar.progress_px(state.time, state.duration, state.w)
    if px ~= state.progress_px then
        state.progress_px = px
        if bar_shown() then painter.request() end
    end
    if not grown() then return end
    local cached = bar.cached_until(state.cache_ranges, state.time)
    local cache_px = cached and bar.progress_px(cached, state.duration, state.w) or -1
    local left, right = controls.time_text(state.time, state.duration, state.remaining)
    if cache_px ~= state.cache_px or left .. right ~= state.time_text then
        state.cache_px, state.time_text = cache_px, left .. right
        painter.request()
    end
end

local function request_if_grown()
    if grown() then painter.request() end
end

painter.set_renderer(function()
    if state.w <= 0 or state.h <= 0 then return "", false end
    local now = mp.get_time()
    animation.set_target(tween, mouse.target(now), now)
    local v = animation.value(tween, now)
    local out = bar.render(state, v, opts, bar.drag_time())
    if v > 0 then
        -- On the timeline, the row shows the time under the cursor.
        local p, hover = mouse.pos(), nil
        if p and state.has_timeline() and (mouse.zone() == "bar" or bar.dragging()) then
            hover = bar.drag_time() or bar.x_to_time(p.x, state.duration, state.w)
        end
        local ass, time_w = controls.render(state, v, painter.measure, hover, opts.icon_style)
        state.time_w = time_w
        out = out == "" and ass or out .. "\n" .. ass
    end
    return out, animation.running(tween, now)
end)

check_version()

mp.observe_property("osd-dimensions", "native", function(_, dim)
    local w, h = 0, 0
    if type(dim) == "table" then w, h = tonumber(dim.w) or 0, tonumber(dim.h) or 0 end
    local changed = state.set("w", w)
    changed = state.set("h", h) or changed
    if not changed then return end
    mouse.release() -- the grid changed under a drag in progress
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
end)

mp.observe_property("duration", "number", function(_, d)
    if state.set("duration", d) then
        -- The duration can grow while playing (streams, files being
        -- written); only a duration that is no longer usable ends a drag.
        if not state.has_timeline() then bar.release(false) end
        update_progress()
    end
    mouse.refresh()
end)

mp.observe_property("pause", "bool", function(_, paused)
    state.set("paused", paused == true)
    mouse.refresh()
end)

-- Outside text, kept to a sane size: a file's metadata can hold a title
-- of megabytes.
local function clean(s)
    if type(s) ~= "string" then return nil end
    s = controls.prefix(s, MAX_TITLE)
    return s ~= "" and s or nil
end

-- Property, type, field in state.
for _, p in ipairs({ { "volume", "number", "volume" }, { "mute", "bool", "mute" },
                     { "fullscreen", "bool", "fullscreen" }, { "media-title", "string", "title" },
                     { "chapter-list", "native", "chapters" } }) do
    mp.observe_property(p[1], p[2], function(_, value)
        state[p[3]] = p[3] == "title" and clean(value) or value
        request_if_grown()
    end)
end

mp.observe_property("osd-font", "string", function(_, font)
    -- Braces and backslashes would break the override block.
    state.font = (font or ""):gsub("[{}\\]", "")
    if state.font == "" then state.font = "sans-serif" end
    request_if_grown()
end)

mp.observe_property("demuxer-cache-state", "native", function(_, c)
    state.cache_ranges = type(c) == "table" and c["seekable-ranges"] or nil
    update_progress()
end)

-- set-title <series> <episode>: a two-line title until the file ends.
-- Both empty (or missing) go back to media-title.
mp.register_script_message("set-title", function(series, episode)
    state.series, state.episode = clean(series), clean(episode)
    if opts.debug then msg.info(("set-title: %s / %s"):format(tostring(state.series), tostring(state.episode))) end
    request_if_grown()
end)

mp.observe_property("display-fps", "number", function(_, fps)
    painter.set_fps(fps)
end)

mp.observe_property("mouse-pos", "native", mouse.on_mouse_pos)

-- A drag never survives a change of file.
local function drop_drag()
    mouse.release(false)
    mouse.refresh()
end
mp.register_event("end-file", function()
    state.series, state.episode = nil, nil
    drop_drag()
end)
mp.register_event("file-loaded", drop_drag)
mp.register_event("shutdown", mouse.shutdown)

state.scale = draw.scale(state.hidpi, opts.scale)
state.remaining = opts.remaining_time
debug_sizes("start")
