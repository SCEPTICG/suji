-- Everything suji knows about the player, in one place. Property observers
-- only write here; drawing code only reads from here.

local M = {
    w = 0, h = 0,     -- window size in OSD pixels (osd-dimensions)
    hidpi = 1,        -- display-hidpi-scale, 1 when unknown
    scale = 1,        -- hidpi * options.scale, see draw.scale()
    time = nil,       -- time-pos in seconds, nil when unknown
    duration = nil,   -- duration in seconds, nil when unknown
    paused = false,
    progress_px = -1, -- progress line end in whole pixels, last value seen
    dirty = true,     -- something visible changed since the last paint
}

-- Set a field and mark the state dirty if the value changed.
-- Returns true when it changed.
function M.set(key, value)
    if M[key] == value then return false end
    M[key] = value
    M.dirty = true
    return true
end

-- The timeline is only shown and clickable when the duration is known.
function M.has_timeline()
    return M.duration ~= nil and M.duration > 0
end

return M
