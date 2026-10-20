-- How much of the timeline is visible, from 0 (at rest) to 1 (fully grown).
--
-- This file decides the feel of suji. compute() is a pure function: it gets
-- a snapshot of the situation and returns a number. The rest of suji works
-- with any value in 0..1, including a fixed 0 or 1, and smooths the changes
-- with a short transition, so this does not need to animate anything.
--
-- input fields:
--   distance       number|nil  Distance in px from the cursor to the bar's
--                              active zone. 0 when the cursor is inside it.
--                              nil when the cursor is outside the window or
--                              has not moved yet.
--   proximity      number      options.proximity already multiplied by the
--                              scale, in the same px as `distance`.
--   idle_time      number      Seconds since the mouse last moved.
--   hide_delay     number      options.hide_delay, in seconds. When the mouse
--                              stops, suji asks for this value again once
--                              `hide_delay` seconds have passed, so a rule
--                              like "idle_time >= hide_delay" just works.
--   on_bar         boolean     The cursor is inside the bar's active zone.
--   paused         boolean     Playback is paused.
--   dragging       boolean     The user is dragging the timeline.
--
-- Questions this function answers:
--   * Does closeness grow linearly, or along a curve (slow at first, then
--     quickly)?
--   * If the mouse stays still in the middle of the video, does the bar
--     hide after hide_delay seconds?
--   * Should it never hide while the cursor is on the bar, or while
--     dragging?
--   * What happens while paused? (Some players keep the bar visible.)

local M = {}

function M.compute(input)
    -- Never hide while the user is working with the bar or has paused.
    if input.dragging or input.on_bar or input.paused then return 1 end
    -- Cursor outside the window, or the mouse has been still long enough.
    if not input.distance then return 0 end
    if input.idle_time >= input.hide_delay then return 0 end
    -- Squared so the bar barely reacts from afar and grows when you go for it.
    -- Clamp first: a negative value squared would turn positive.
    local v = 1 - input.distance / input.proximity
    v = math.max(0, math.min(1, v))
    return v * v
end

return M
