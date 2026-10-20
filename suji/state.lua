-- Everything suji knows about the player: observers write, drawing reads.

local M = {
    w = 0, h = 0,     -- window size in OSD pixels (osd-dimensions)
    hidpi = 1,        -- display-hidpi-scale, 1 when unknown
    scale = 1,        -- hidpi * options.scale, see draw.scale()
    time = nil,       -- time-pos in seconds, nil when unknown
    duration = nil,   -- duration in seconds, nil when unknown
    paused = false,
    volume = 100, mute = false, fullscreen = false,
    title = nil,      -- media-title (see controls.file_title), cut; nil when empty
    series = nil,     -- two-line title sent with set-title, nil when unset
    episode = nil,
    font = "sans-serif", -- osd-font
    remaining = false,   -- show the remaining time instead of the duration
    chapters = {},       -- chapter-list
    cache_ranges = nil,  -- seekable-ranges of demuxer-cache-state
    -- Last values seen, to repaint only when what is shown changes:
    progress_px = -1, -- progress line end in whole pixels
    cache_px = -1,    -- end of the cached range in whole pixels
    time_text = "",   -- the time as shown
    time_w = 0,       -- measured width of the time, for its click zone
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
