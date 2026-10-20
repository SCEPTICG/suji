-- Mouse position, distance to the bar, the active zone and the click
-- bindings.
--
-- MBTN_LEFT is only bound while the cursor is over the visible bar (or a
-- drag is in progress). Everywhere else the click goes through, so double
-- click for fullscreen and window dragging keep working.

local msg = require "mp.msg"
local opts = require "options"
local state = require "state"
local painter = require "painter"
local visibility = require "visibility"
local bar = require "elements.bar"

local M = {}

local pos           -- { x, y } in OSD pixels, nil when unknown or outside
local seen_real = false
local last_move = 0
local on_bar = false
local bound = false
local reported_error = false

-- Fires once, hide_delay seconds after the last movement, so a
-- visibility rule based on idle_time gets evaluated at the right moment.
-- The small margin covers the timer resolution.
local idle_timer = mp.add_timeout(1, function() M.refresh() end, true)

function M.input(now)
    local distance
    if pos then distance = math.max(0, bar.zone_top(state.h, state.scale) - pos.y) end
    return {
        distance = distance,
        proximity = opts.proximity * state.scale,
        idle_time = now - last_move,
        hide_delay = opts.hide_delay,
        on_bar = on_bar,
        paused = state.paused,
        dragging = bar.dragging(),
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

local function on_button(e)
    if e.event == "down" then
        if pos then bar.press(pos.x, state, opts) end
    elseif e.event == "up" then
        bar.release(not e.canceled)
    elseif e.event == "press" then
        -- Down and up could not be tracked separately: treat it as a click.
        if pos then bar.press(pos.x, state, opts); bar.release() end
    end
    M.refresh()
end

local function set_bindings(enable)
    if enable == bound then return end
    bound = enable
    if enable then
        mp.add_forced_key_binding("MBTN_LEFT", "suji-bar", on_button, { complex = true })
        -- Swallow double clicks on the bar so they do not toggle fullscreen.
        mp.add_forced_key_binding("MBTN_LEFT_DBL", "suji-bar-dbl", function() end)
    else
        mp.remove_key_binding("suji-bar")
        mp.remove_key_binding("suji-bar-dbl")
    end
end

-- Re-evaluate the bindings and ask for a paint. Bindings are switched on as
-- soon as the cursor enters the zone, never on the click itself, because
-- mpv applies them asynchronously and the first click would be lost.
function M.refresh()
    local want = bar.dragging() or
        (on_bar and state.has_timeline() and M.target(mp.get_time()) > 0)
    set_bindings(want)
    painter.request()
end

local function update_zone()
    on_bar = pos ~= nil and bar.in_zone(pos.x, pos.y, state.w, state.h, state.scale)
end

-- Observer for the mouse-pos property.
function M.on_mouse_pos(_, p)
    if type(p) ~= "table" or not p.hover then
        pos = nil
        bar.release()
    elseif seen_real or p.x ~= 0 or p.y ~= 0 then
        -- Some backends report (0, 0) before the first real movement.
        seen_real = true
        if not pos or pos.x ~= p.x or pos.y ~= p.y then
            pos = { x = p.x, y = p.y }
            last_move = mp.get_time()
            bar.move(p.x, state)
            idle_timer.timeout = opts.hide_delay + 0.05
            idle_timer:kill()
            idle_timer:resume()
        end
    end
    update_zone()
    M.refresh()
end

-- The window changed size: the zone moved with it.
function M.on_resize()
    update_zone()
    M.refresh()
end

return M
