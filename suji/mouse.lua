-- Mouse position, distance to the bar, the active zone and the bindings.
-- MBTN_LEFT is only bound over a visible zone (bar, button, time, volume
-- slider) or while dragging, the wheel only over the volume; elsewhere input
-- goes through, so double click and window dragging keep working. Forced
-- bindings still let mpv start a window drag that cancels ours, so
-- input-builtin-dragging is off while they are on (see restore_dragging).

local msg = require "mp.msg"
local opts = require "options"
local state = require "state"
local painter = require "painter"
local visibility = require "visibility"
local bar = require "elements.bar"
local controls = require "elements.controls"

local M = {}

local pos           -- { x, y } in OSD pixels, nil when unknown or outside
local seen_real = false
local last_move = 0
local zone          -- "bar", a control name (see controls.hit) or nil
local volume_drag = false
local bound, wheel_bound = false, false
local took_dragging = false -- suji set input-builtin-dragging=no
local reported_error = false

-- Re-evaluates visibility once the mouse has been still hide_delay (M.rearm).
local idle_timer = mp.add_timeout(1, function() M.refresh() end, true)

function M.input(now)
    local distance
    if pos then distance = math.max(0, bar.zone_top(state.h, state.scale) - pos.y) end
    return {
        distance = distance,
        proximity = opts.proximity * state.scale,
        idle_time = now - last_move,
        hide_delay = opts.hide_delay,
        on_bar = zone == "bar",
        on_controls = zone ~= nil and zone ~= "bar",
        paused = state.paused,
        dragging = bar.dragging() or volume_drag,
    }
end

-- visibility.compute(), guarded: an error or a non-number counts as 0.
function M.target(now)
    local ok, v = pcall(visibility.compute, M.input(now))
    if not ok or type(v) ~= "number" or v ~= v then
        if not reported_error then
            reported_error = true
            msg.error("visibility.compute failed or returned no number: " .. tostring(v))
        end
        return 0
    end
    return math.max(0, math.min(1, v))
end

function M.pos() return pos end
function M.zone() return zone end

local function set_volume(x)
    local v = controls.x_to_volume(x, controls.layout(state.w, state.h, state.scale))
    if v ~= state.volume then mp.commandv("set", "volume", tostring(v)) end
end

local function press(x)
    if zone == "bar" then bar.press(x, state, opts)
    elseif zone == "volume" then volume_drag = true; set_volume(x)
    elseif zone == "pause" then mp.commandv("cycle", "pause")
    elseif zone == "mute" then mp.commandv("cycle", "mute")
    elseif zone == "fullscreen" then mp.commandv("cycle", "fullscreen")
    elseif zone == "time" then
        state.remaining = not state.remaining
        if opts.debug then msg.info("remaining time " .. (state.remaining and "on" or "off")) end
    end
end

-- End any drag, of the timeline or of the volume. seek as in bar.release.
function M.release(seek)
    bar.release(seek)
    volume_drag = false
end
local release = M.release

local function on_button(e)
    if e.event == "down" then
        if pos then press(pos.x) end
    elseif e.event == "up" then
        release(not e.canceled)
    elseif e.event == "press" then
        -- Down and up could not be tracked separately: treat it as a click.
        if pos then press(pos.x); release() end
    end
    M.refresh()
end

local function wheel(step)
    return function() mp.commandv("add", "volume", step) end
end

-- Put window dragging back, unless someone changed it since suji turned
-- it off. A write of "no" by another script in the meantime cannot be
-- told apart: the value does not change, so not even an observer sees it.
local function restore_dragging()
    if not took_dragging then return end
    took_dragging = false
    if mp.get_property_bool("input-builtin-dragging") == false then
        mp.set_property_bool("input-builtin-dragging", true)
    end
end

local function set_bindings(enable, wheel_too)
    if wheel_too ~= wheel_bound then
        wheel_bound = wheel_too
        if wheel_too then
            mp.add_forced_key_binding("WHEEL_UP", "suji-wheel-up", wheel("5"))
            mp.add_forced_key_binding("WHEEL_DOWN", "suji-wheel-down", wheel("-5"))
        else
            mp.remove_key_binding("suji-wheel-up")
            mp.remove_key_binding("suji-wheel-down")
        end
    end
    if enable == bound then return end
    bound = enable
    if enable then
        if mp.get_property_bool("input-builtin-dragging") == true then
            mp.set_property_bool("input-builtin-dragging", false)
            took_dragging = true
        end
        mp.add_forced_key_binding("MBTN_LEFT", "suji-bar", on_button, { complex = true })
        -- Swallow double clicks on our zones so they do not toggle fullscreen.
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "suji-bar-dbl", function() end)
    else
        mp.remove_key_binding("suji-bar")
        mp.remove_key_binding("suji-bar-dbl")
        restore_dragging()
    end
end

-- Leave the player as suji found it.
function M.shutdown()
    set_bindings(false, false)
    restore_dragging()
end

-- Re-evaluate the bindings and ask for a paint. Bindings are switched on as
-- soon as the cursor enters the zone, never on the click itself, because
-- mpv applies them asynchronously and the first click would be lost.
function M.refresh()
    if not opts.enabled then pos, zone = nil, nil; idle_timer:kill() end
    local usable = zone ~= nil and (zone ~= "bar" or state.has_timeline())
    local want = bar.dragging() or volume_drag or (usable and M.target(mp.get_time()) > 0)
    set_bindings(want, want and (zone == "mute" or zone == "volume"))
    painter.request()
end

local function update_zone()
    if not pos then zone = nil
    elseif bar.in_zone(pos.x, pos.y, state.w, state.h, state.scale) then zone = "bar"
    else
        zone = controls.hit(controls.layout(state.w, state.h, state.scale), pos.x, pos.y, state.time_w)
    end
end

-- Observer for the mouse-pos property.
function M.on_mouse_pos(_, p)
    if not opts.enabled then return end
    if type(p) ~= "table" or not p.hover then
        pos = nil
        release()
        idle_timer:kill()
    elseif seen_real or p.x ~= 0 or p.y ~= 0 then
        -- Some backends report (0, 0) before the first real movement.
        seen_real = true
        if not pos or pos.x ~= p.x or pos.y ~= p.y then
            pos = { x = p.x, y = p.y }
            last_move = mp.get_time()
            bar.move(p.x, state)
            if volume_drag then set_volume(p.x) end
            M.rearm()
        end
    end
    update_zone()
    M.refresh()
end

-- Idle timer to hide_delay after the last move (+ margin for its resolution).
function M.rearm()
    idle_timer:kill()
    local left = last_move + opts.hide_delay + 0.05 - mp.get_time()
    if pos and left > 0 then
        idle_timer.timeout = left
        idle_timer:resume()
    end
end

-- The window changed size: the zone moved with it.
function M.on_resize()
    update_zone()
    M.refresh()
end

return M
