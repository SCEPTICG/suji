-- The only module that calls overlay:update().
--
-- Paint requests are grouped by a single timer and capped at the display
-- frame rate. A frame is only sent to mpv when its ASS text or the overlay
-- size changed. While nothing is animating, no timer is left running.

local state = require "state"

local M = {}

local overlay = mp.create_osd_overlay("ass-events")
local min_interval = 1 / 60
local last_paint = 0
local last_data, last_w, last_h
local render -- function() -> ass_text, keep_animating

local timer -- created disabled below, re-armed on demand

local function flush()
    last_paint = mp.get_time()
    if not render then return end
    local data, animating = render()
    if data ~= last_data or state.w ~= last_w or state.h ~= last_h then
        last_data, last_w, last_h = data, state.w, state.h
        overlay.res_x, overlay.res_y = state.w, state.h
        overlay.data = data
        overlay:update()
    end
    if animating then M.request() end
end

timer = mp.add_timeout(min_interval, flush, true)

function M.set_renderer(fn)
    render = fn
end

-- Follow the display refresh rate, within sane limits.
function M.set_fps(fps)
    fps = tonumber(fps)
    if not fps or fps < 24 or fps > 360 then fps = 60 end
    min_interval = 1 / fps
end

-- Ask for a paint. Several requests before the next frame become one.
function M.request()
    if timer:is_enabled() then return end
    local wait = last_paint + min_interval - mp.get_time()
    timer.timeout = wait > 0 and wait or 0
    timer:kill()
    timer:resume()
end

-- Width in px of one event of ASS text, measured by libass in a hidden
-- overlay. That is slow, so results are cached; guess is used (and not
-- cached) when mpv cannot tell.
local probe = mp.create_osd_overlay("ass-events")
probe.hidden, probe.compute_bounds = true, true
local widths, cached = {}, 0

function M.measure(ass, guess)
    if widths[ass] then return widths[ass] end
    probe.res_x, probe.res_y = state.w, state.h
    probe.data = ass
    local r = probe:update()
    if type(r) ~= "table" or not r.x0 or not r.x1 then return guess end
    local w = r.x1 - r.x0
    if cached >= 256 then widths, cached = {}, 0 end
    widths[ass], cached = w, cached + 1
    return w
end

return M
