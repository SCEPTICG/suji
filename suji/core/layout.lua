-- Where the row goes and what is under the cursor. place() and hit() are
-- pure; current() lays out the row of now (see modules.row) and adds the
-- timeline's zone on top of it. From the bottom edge up: a margin, the row
-- and the timeline.
--
-- Elements go from the left margin to the right, GAP apart. A space takes
-- the free width: with one, what follows it is aligned to the right edge;
-- with several, they share the free width. A gap is a small fixed hole.

local state = require "core.state"
local modules = require "core.modules"

local M = {}

-- Sizes in px at scale 1.
M.ROW_LIFT = 40 -- centre of the row above the bottom edge
M.SIDE = 20     -- row margin on both sides
M.GAP = 8       -- between two elements
M.GAP_ITEM = 8  -- width of a gap element (so 24 px between its neighbours)
M.HEIGHT = 44   -- height of every zone of the row

local function width(it, s) return it.gap and M.GAP_ITEM * s or it.width end

-- items: { mod, width } | { gap = true } | { space = true }, in order.
-- geo: { w, h, scale }. Returns { boxes = { { mod, x0, y0, x1, y1, cy } } }.
function M.place(items, geo)
    local s = geo.scale
    local cy = geo.h - M.ROW_LIFT * s
    local y0, y1 = cy - M.HEIGHT * s / 2, cy + M.HEIGHT * s / 2
    local left, right, gap = M.SIDE * s, geo.w - M.SIDE * s, M.GAP * s

    -- Groups of elements between spaces, and the width each one takes.
    local groups, spans, used = { {} }, {}, 0
    for _, it in ipairs(items) do
        if it.space then groups[#groups + 1] = {} else table.insert(groups[#groups], it) end
    end
    for g, list in ipairs(groups) do
        local n = 0
        for i, it in ipairs(list) do n = n + width(it, s) + (i > 1 and gap or 0) end
        spans[g], used = n, used + n
    end
    -- Can be negative in a small window: then the groups overlap.
    local flex = #groups > 1 and (right - left - used) / (#groups - 1) or 0

    local out = { boxes = {} }
    local x = left
    for g, list in ipairs(groups) do
        if g > 1 then x = x + flex end
        -- The last group is laid out from the right edge, so it stays exact.
        if g > 1 and g == #groups then x = right - spans[g] end
        for i, it in ipairs(list) do
            if i > 1 then x = x + gap end
            local x1 = x + width(it, s)
            if it.mod then
                out.boxes[#out.boxes + 1] = { mod = it.mod, x0 = x, y0 = y0, x1 = x1, y1 = y1, cy = cy }
            end
            x = x1
        end
    end
    return out
end

-- The first zone for which test(zone) holds: the timeline's (placed.bar)
-- first, then the boxes of the row in order.
local function first(placed, test)
    if placed.bar and test(placed.bar) then return placed.bar end
    for _, b in ipairs(placed.boxes) do
        if test(b) then return b end
    end
end

-- The zone under (x, y), or nil.
function M.hit(placed, x, y)
    return first(placed, function(z) return x >= z.x0 and x < z.x1 and y >= z.y0 and y < z.y1 end)
end

-- The zone or box of module mod, nil when it is not laid out.
function M.find(placed, mod)
    return first(placed, function(z) return z.mod == mod end)
end

-- The box of the row's element called name in the controls option
-- ("more", "command:x", "button:name"; see modules.name_of), or nil.
function M.named(placed, name)
    for _, b in ipairs(placed.boxes) do
        if modules.name_of(b.mod) == name then return b end
    end
end

-- The timeline's zone: the whole width, just above the row (with the row
-- empty too), where the grown bar is.
function M.bar_zone()
    local tl = modules.timeline
    return { mod = tl, bar = true, x0 = 0, y0 = tl.zone_top(state.h, state.scale),
             x1 = state.w, y1 = tl.zone_bottom(state.h, state.scale) }
end

-- The row and the timeline's zone as they are now.
function M.current()
    local placed = M.place(modules.row(), state)
    placed.bar = M.bar_zone()
    return placed
end

return M
