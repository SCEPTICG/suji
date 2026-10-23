-- prev and next: the previous and the next entry of the playlist, files or
-- streams alike. Shown only when the playlist has more than one entry, and
-- each one hides, leaving no gap, at its end of the playlist: prev on the
-- first entry, next on the last.

local M = {}

-- dir: -1 for prev, 1 for next.
function M.new(dir)
    local b = { once = true } -- a double click skips one entry, not two
    local count, pos = 0, -1 -- playlist-count, playlist-pos

    -- Whether there is an entry that way.
    local function shown()
        if count < 2 or pos < 0 then return false end
        if dir < 0 then return pos > 0 end
        return pos < count - 1
    end

    function b.init(ctx)
        local function update(c, p)
            local before = shown()
            count, pos = c or count, p or pos
            if shown() ~= before then ctx.relayout() end
        end
        -- native, as the has_playlist condition watches it: one observer
        ctx.watch("playlist-count", "native", function(n) update(tonumber(n) or 0, nil) end)
        ctx.watch("playlist-pos", "native", function(n) update(nil, tonumber(n) or -1) end)
    end

    b.available = shown

    function b.width(ctx) return ctx.BUTTON * ctx.state.scale end

    function b.render(ctx, box, v)
        return ctx.icon(dir < 0 and "prev" or "next", (box.x0 + box.x1) / 2, box.cy, v)
    end

    function b.press() mp.commandv(dir < 0 and "playlist-prev" or "playlist-next") end

    return b
end

return M
