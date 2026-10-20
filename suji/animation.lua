-- Clock-based transitions. A tween moves a value towards a target over a
-- fixed duration, so it takes the same time at 30 Hz or at 144 Hz.
-- No mpv dependencies: the caller passes the current time in seconds.

local M = {}

local function ease_out_cubic(p)
    local inv = 1 - p
    return 1 - inv * inv * inv
end

function M.new(duration, value)
    value = value or 0
    return { duration = duration, from = value, to = value, start = 0 }
end

function M.value(tw, now)
    if tw.duration <= 0 then return tw.to end
    local p = (now - tw.start) / tw.duration
    if p >= 1 or p ~= p then return tw.to end
    if p < 0 then p = 0 end
    return tw.from + (tw.to - tw.from) * ease_out_cubic(p)
end

-- Start a new transition from wherever the value is right now. Calling it
-- again with the same target does not restart the clock.
function M.set_target(tw, target, now)
    if target == tw.to then return end
    tw.from = M.value(tw, now)
    tw.to = target
    tw.start = now
end

-- True while the value has not reached its target yet.
function M.running(tw, now)
    return tw.from ~= tw.to and now - tw.start < tw.duration
end

return M
