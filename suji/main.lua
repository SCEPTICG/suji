-- suji: a minimal on-screen controller for mpv.
-- Entry point: version check, the core's property observers, the modules,
-- the controls option and the frame renderer. The core is in core/, the
-- elements it draws in modules/ (see core/modules.lua). Menus are a service
-- of the core (core/menu.lua) that modules use, and other scripts through
-- messages (core/messages.lua), which also show action buttons
-- (modules/actions.lua). Thumbnails on the timeline come from thumbfast
-- (core/thumbnail.lua).

local msg = require "mp.msg"
local opts = require "core.options"
local state = require "core.state"
local draw = require "core.draw"
local text = require "core.text"
local animation = require "core.animation"
local painter = require "core.painter"
local modules = require "core.modules"
local layout = require "core.layout"
local mouse = require "core.mouse"
local menu = require "core.menu"
local size = require "core.size"
local thumbnail = require "core.thumbnail"
local actions = require "modules.actions"
require "core.messages"

local watch, ctx, timeline = modules.watch, modules.ctx, modules.timeline

local VERSION = "0.6.1" -- sent to every script at start, as suji-version
local ENABLED = "user-data/suji/enabled" -- true while suji is on (docs/api.md)
local VERSION_PROP = "user-data/suji/version" -- VERSION while suji is loaded
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
    if not opts.debug or not reason then return end
    msg.info(("%s: osd-dimensions %dx%d, display-hidpi-scale %s, scale option %s, size %d%%, scale %.3f")
        :format(reason, math.floor(state.w), math.floor(state.h), tostring(mp.get_property_number("display-hidpi-scale")),
            tostring(opts.scale), size.percent(), state.scale))
end

-- user-data/suji/margins = { bottom = N }: N px from the bottom edge to
-- the top of the row (the timeline's zone when the row is empty), for
-- scripts that draw near it (docs/api.md). The same whether the controls
-- are shown or hidden: it only follows the window, the scale and the row.
-- Written when it changes; deleted while suji is off.
local margin
local function publish_margins()
    local m
    if opts.enabled and state.h > 0 then
        local placed = layout.current()
        m = math.ceil(state.h - (placed.boxes[1] or placed.bar).y0)
    end
    if m == margin then return end
    margin = m
    mp.set_property_native("user-data/suji/margins", m and { bottom = m } or nil)
end

-- The zones moved: the window, the scale or the row changed.
local function on_layout()
    actions.on_layout()
    mouse.on_layout()
    publish_margins()
end

-- Visibility changes are smoothed by a short clock-based transition.
local tween = animation.new(0.15)

-- The controls, title and grown bar are on screen (visibility above 0).
local function grown()
    if not opts.enabled then return false end
    local now = mp.get_time()
    return animation.value(tween, now) > 0 or animation.running(tween, now)
end
ctx.visible = grown

-- The time under the cursor, on the timeline or dragging it.
local function cursor_time()
    local p = mouse.pos()
    if p and state.has_timeline() and (mouse.on_bar() or mouse.captured() == timeline) then
        return timeline.drag_time() or timeline.x_to_time(p.x, state.duration, state.w)
    end
end

-- thumbnail.update and render, protected like a module's calls: the
-- first error is logged, takes the thumbnail away and turns it off.
local thumbnail_failed = false
local function thumbnail_call(fname, ...)
    if thumbnail_failed then return nil end
    local ok, r = pcall(thumbnail[fname], ...)
    if ok then return r end
    thumbnail_failed = true
    msg.error("thumbnails failed and were turned off: " .. draw.printable(r, 300))
    pcall(thumbnail.clear)
end

-- The row shows it too, unless the thumbnail's box already does.
function ctx.hover_time()
    if thumbnail.shown() then return nil end
    return cursor_time()
end

painter.set_renderer(function()
    if not opts.enabled or state.w <= 0 or state.h <= 0 then return "", false end
    local now = mp.get_time()
    animation.set_target(tween, mouse.target(now), now)
    local v = animation.value(tween, now)
    local out, remeasured = {}, false
    local function add(ass) if ass and ass ~= "" then out[#out + 1] = ass end end
    -- Before the row: it decides which time the row shows.
    local p = mouse.pos()
    thumbnail_call("update", v > 0 and cursor_time() or nil, p and p.x)
    add(modules.call(timeline, "render", layout.bar_zone(), v))
    if v > 0 then
        local placed = layout.current()
        for _, box in ipairs(placed.boxes) do add(modules.call(box.mod, "render", box, v)) end
        local row_top = state.h - (layout.ROW_LIFT + layout.HEIGHT / 2) * state.scale
        local measured = modules.title.measured
        add(modules.call(modules.title, "render", { x0 = 0, y0 = 0, x1 = placed.right_x0, y1 = row_top },
            v * menu.title_opacity(now)))
        -- Its opacity came from the old width: once more under an open menu.
        remeasured = modules.title.measured ~= measured and menu.is_open()
    end
    -- Also with the controls hidden: a skip should need no mouse move.
    local actions_ass, actions_running = actions.render(now)
    add(actions_ass)
    -- Over the row and the action buttons it covers: none shows through.
    if v > 0 then add(thumbnail_call("render", v)) end
    local menu_ass, menu_running = menu.render(now) -- on top of everything
    add(menu_ass)
    return table.concat(out, "\n"), animation.running(tween, now) or menu_running or actions_running or remeasured
end)

check_version()

watch("osd-dimensions", "native", function(dim)
    local w, h = 0, 0
    if type(dim) == "table" then w, h = tonumber(dim.w) or 0, tonumber(dim.h) or 0 end
    local changed = state.set("w", w)
    changed = state.set("h", h) or changed
    if not changed then return end
    mouse.release() -- the grid changed under a drag in progress
    debug_sizes("resize")
    on_layout()
end)

-- The size factor changed (HiDPI, the scale option or the size chosen in
-- the more menu): zones move too.
local function rescale(reason)
    state.scale = draw.scale(state.hidpi, size.scale(opts.scale, opts.LIMITS.scale))
    debug_sizes(reason)
    on_layout()
end

watch("display-hidpi-scale", "number", function(scale)
    state.hidpi = scale or 1
    rescale("hidpi")
end)

watch("time-pos", "number", function(t) state.time = t end)

watch("duration", "number", function(d)
    -- A growing duration (streams) keeps a drag; an unusable one ends it.
    if state.set("duration", d) and not state.has_timeline() and mouse.captured() == timeline then
        mouse.release(false)
    end
    mouse.refresh()
end)

watch("pause", "bool", function(paused)
    state.set("paused", paused == true)
    mouse.refresh()
end)

-- Outside text, cut to a sane size (metadata can hold megabytes).
local function clean(s)
    if type(s) ~= "string" then return nil end
    s = text.prefix(s, MAX_TITLE)
    return s ~= "" and s or nil
end

-- The title comes from three properties, see text.file_title.
local names = {}
for _, p in ipairs({ "media-title", "filename", "filename/no-ext" }) do
    watch(p, "string", function(value)
        names[p] = value
        state.title = clean(text.file_title(names["media-title"], names.filename, names["filename/no-ext"]))
        return true
    end)
end

watch("osd-font", "string", function(font)
    -- Braces and backslashes would break the override block.
    state.font = (font or ""):gsub("[{}\\]", "")
    if state.font == "" then state.font = "sans-serif" end
    return true
end)

-- set-title <series> <episode>: two lines until the file ends, one with
-- only one of them, media-title with neither. See the README.
mp.register_script_message("set-title", function(series, episode)
    state.series, state.episode = clean(series), clean(episode)
    if opts.debug then msg.info(("set-title: %s / %s"):format(draw.printable(state.series), draw.printable(state.episode))) end
    if grown() then painter.request() end
end)

watch("display-fps", "number", function(fps) painter.set_fps(fps) end)

watch("mouse-pos", "native", mouse.on_mouse_pos)

-- The modules' own observers come after the core's, so they see the state
-- already updated. Then the row, which may watch more for its conditions.
modules.init()
modules.set_controls(opts.controls)
modules.on_layout(on_layout)

-- A drag never survives a change of file.
local function drop_drag()
    mouse.release(false)
    mouse.refresh()
end
mp.register_event("end-file", function()
    state.series, state.episode = nil, nil
    thumbnail.clear()
    drop_drag()
end)
-- The timeline is not optional: if it failed, each new file gets it back.
mp.register_event("file-loaded", function()
    modules.revive(timeline)
    drop_drag()
end)
mp.register_event("shutdown", function()
    mouse.shutdown()
    mp.set_property_native(ENABLED, nil) -- nil: observers hear it too
    mp.set_property_native(VERSION_PROP, nil)
end)

-- One interface at a time: osc=no at run time unloads mpv's OSC. It is
-- turned back on when disabled only if suji turned it off.
local took_osc = false
-- osc turned on by someone else after suji took it: it is theirs now, and
-- suji leaves it as it is when turned off. suji itself only writes yes
-- when it gives the OSC back, and stops holding it then.
watch("osc", "bool", function(on)
    if took_osc and on == true then took_osc = false end
end)
local function set_enabled(on)
    if on and mp.get_property_bool("osc") == true then
        mp.set_property_bool("osc", false)
        took_osc = true
    elseif not on then
        menu.close(true)
        actions.hide(nil, true)
        thumbnail.clear()
        mouse.release(false)
        if took_osc and mp.get_property_bool("osc") == false then mp.set_property_bool("osc", true) end
        took_osc = false
        tween = animation.new(0.15) -- no fade out when enabled again
    end
    if opts.debug then msg.info(on and "enabled" or "disabled") end
    -- Bindings and a paint (empty when disabled); a still cursor is read now.
    if on then mouse.on_mouse_pos(mp.get_property_native("mouse-pos")) else mouse.refresh() end
end

-- Options changed at run time; the rest is read where it is used.
opts.on_update(function(changed)
    if changed.remaining_time then state.remaining = opts.remaining_time end
    if changed.enabled then
        mp.set_property_native(ENABLED, opts.enabled)
        set_enabled(opts.enabled)
    end
    if changed.hide_delay then mouse.rearm() end
    if changed.controls then modules.set_controls(opts.controls) end
    rescale(changed.scale and "options" or nil) -- lays out and paints
end)

state.remaining = opts.remaining_time
if opts.enabled then set_enabled(true) end
size.load()
size.on_change(function() rescale("size") end)
rescale("start")

-- Last, so a start that failed leaves no true behind. Still while the
-- script loads: mpv plays nothing until every script has, so a script
-- loaded before suji already sees it on its first file-loaded. The
-- version goes first, so enabled set means version set too, and it stays
-- with enabled=no: suji is still there and still listens.
mp.set_property_native(VERSION_PROP, VERSION)
mp.set_property_native(ENABLED, opts.enabled)

-- Tell the scripts already running that suji is here (see docs/api.md).
mp.commandv("script-message", "suji-version", VERSION)
