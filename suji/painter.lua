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
    state.dirty = false
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

function M.clear()
    timer:kill()
    overlay:remove()
    last_data = nil
end

return M
