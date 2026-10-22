-- What the core knows about the player: observers write, drawing reads.
-- Modules keep what only they need (volume, chapters...) to themselves.

local M = {
    w = 0, h = 0,     -- window size in OSD pixels (osd-dimensions)
    hidpi = 1,        -- display-hidpi-scale, 1 when unknown
    scale = 1,        -- hidpi * options.scale * the size, see draw.scale()
    time = nil,       -- time-pos in seconds, nil when unknown
    duration = nil,   -- duration in seconds, nil when unknown
    paused = false,
    title = nil,      -- media-title (see text.file_title), cut; nil when empty
    series = nil,     -- two-line title sent with set-title, nil when unset
    episode = nil,
    font = "sans-serif", -- osd-font
    remaining = false,   -- show the remaining time instead of the duration
}

-- Set a field. Returns true when the value changed.
function M.set(key, value)
    if M[key] == value then return false end
    M[key] = value
    return true
end

-- A duration the timeline can use: known, positive and finite.
function M.valid_duration(d)
    return type(d) == "number" and d > 0 and d < math.huge
end

-- The timeline is only shown and clickable when the duration is usable.
function M.has_timeline()
    return M.valid_duration(M.duration)
end

return M
