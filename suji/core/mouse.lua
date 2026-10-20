-- Mouse position, distance to the bar, the zone under the cursor and the
-- bindings. Zones come from the layout: the timeline's along the bottom
-- edge and one per module of the row. A module whose press returns true
-- holds the mouse until the button goes up (dragging).
-- MBTN_LEFT is only bound over a visible zone or while a module holds the
-- mouse, the wheel only over a module that takes it; elsewhere input goes
-- through, so double click and window dragging keep working. Forced
-- bindings still let mpv start a window drag that cancels ours, so
-- input-builtin-dragging is off while they are on (see restore_dragging).
-- An open menu (core/menu.lua) comes first: MBTN_LEFT is bound everywhere,
-- a click on the menu is a choice and a click anywhere else only closes
-- it, and the controls stay on screen.

local msg = require "mp.msg"
local opts = require "core.options"
local state = require "core.state"
local painter = require "core.painter"
local visibility = require "core.visibility"
local layout = require "core.layout"
local modules = require "core.modules"
local menu = require "core.menu"

local M = {}

local pos           -- { x, y } in OSD pixels, nil when unknown or outside
local seen_real = false
local last_move = 0
local hit           -- zone under the cursor (see layout.hit) or nil
local captured      -- module holding the mouse, or nil
local bound, wheel_bound = false, false
local took_dragging = false -- suji set input-builtin-dragging=no
local reported_error = false

-- Re-evaluates visibility once the mouse has been still hide_delay (M.rearm).
local idle_timer = mp.add_timeout(1, function() M.refresh() end, true)

function M.input(now)
    local distance
    if pos then distance = math.max(0, layout.bar_zone().y0 - pos.y) end
    return {
        distance = distance,
        proximity = opts.proximity * state.scale,
        idle_time = now - last_move,
        hide_delay = opts.hide_delay,
        on_bar = hit ~= nil and hit.bar == true,
        on_controls = (hit ~= nil and not hit.bar) or menu.is_open(),
        paused = state.paused,
        dragging = captured ~= nil,
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
function M.on_bar() return hit ~= nil and hit.bar == true end
function M.captured() return captured end

-- End what the module holding the mouse is doing. commit = false drops it
-- (no final seek, for example); see the module contract.
function M.release(commit)
    local mod = captured
    if not mod then return end
    captured = nil
    modules.call(mod, "release", commit)
end
local release = M.release

local function press(x, y)
    if captured then release(false) end -- its button up was lost
    if menu.is_open() then
        if menu.contains(x, y) then menu.press(x, y) else menu.close() end
        return
    end
    if hit and modules.call(hit.mod, "press", hit, x, y) == true then captured = hit.mod end
end

-- The cursor moved while a module holds the mouse. It gets its box of now;
-- if it is no longer laid out, it lets go.
local function drag(x, y)
    local box = layout.find(layout.current(), captured)
    if not box then return release(false) end
    modules.call(captured, "move", box, x, y)
end

local function on_button(e)
    if e.event == "down" then
        if pos then press(pos.x, pos.y) end
    elseif e.event == "up" then
        release(not e.canceled)
    elseif e.event == "press" then
        -- Down and up could not be tracked separately: treat it as a click.
        if pos then press(pos.x, pos.y); release() end
    end
    M.refresh()
end

local function wheel(dir)
    return function()
        if pos and menu.contains(pos.x, pos.y) then menu.wheel(dir)
        elseif hit then modules.call(hit.mod, "wheel", dir) end
    end
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
            mp.add_forced_key_binding("WHEEL_UP", "suji-wheel-up", wheel(1))
            mp.add_forced_key_binding("WHEEL_DOWN", "suji-wheel-down", wheel(-1))
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
    menu.close(true)
    set_bindings(false, false)
    restore_dragging()
end

-- Re-evaluate the bindings and ask for a paint. Bindings are switched on as
-- soon as the cursor enters the zone, never on the click itself, because
-- mpv applies them asynchronously and the first click would be lost.
function M.refresh()
    if not opts.enabled then pos, hit = nil, nil; idle_timer:kill() end
    local usable = hit ~= nil and (not hit.bar or state.has_timeline())
    local want = captured ~= nil or menu.is_open() or (usable and M.target(mp.get_time()) > 0)
    local on_menu = pos ~= nil and menu.contains(pos.x, pos.y)
    set_bindings(want, want and (on_menu or (hit ~= nil and modules.takes(hit.mod, "wheel"))))
    painter.request()
end

local function update_zone()
    hit = pos and layout.hit(layout.current(), pos.x, pos.y) or nil
end

-- Observer for the mouse-pos property.
function M.on_mouse_pos(p)
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
            if captured then drag(p.x, p.y) end
            M.rearm()
        end
    end
    update_zone()
    menu.pointer(pos and pos.x, pos and pos.y)
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

-- The zones moved: the window size, the scale or the row changed. A module
-- that is no longer laid out lets go of the mouse.
function M.on_layout()
    menu.on_layout()
    if captured and not layout.find(layout.current(), captured) then release(false) end
    update_zone()
    M.refresh()
end

-- A module that failed loses the mouse and its zone. If it held the
-- mouse, it is still told to drop what it was doing (a pause it set, a
-- timer), protected: it is off, so modules.call would not reach it.
menu.on_change(M.refresh)

modules.on_failure(function(mod)
    if captured == mod then
        captured = nil
        if type(mod.release) == "function" then pcall(mod.release, modules.ctx_of(mod), false) end
    end
    if hit and hit.mod == mod and not hit.bar then hit = nil end
    M.refresh()
end)

return M
