-- Where the row goes and what is under the cursor. place() and hit() are
-- pure; current() lays out the row of now (see modules.row) and adds the
-- timeline's zone along the bottom edge.
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
-- geo: { w, h, scale }. Returns { boxes = { { mod, x0, y0, x1, y1, cy } },
-- right_x0 }: right_x0 is where the first element after the first space
-- starts, or the right margin when there is none.
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

    local out, found = { boxes = {}, right_x0 = right }, false
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
                if g > 1 and not found then out.right_x0, found = x, true end
            end
            x = x1
        end
    end
    return out
end

local function inside(z, x, y) return x >= z.x0 and x < z.x1 and y >= z.y0 and y < z.y1 end

-- The zone under (x, y): the timeline's (placed.bar, checked first), the
-- box of a module of the row, or nil.
function M.hit(placed, x, y)
    if placed.bar and inside(placed.bar, x, y) then return placed.bar end
    for _, b in ipairs(placed.boxes) do
        if inside(b, x, y) then return b end
    end
end

-- The zone or box of module mod, nil when it is not laid out.
function M.find(placed, mod)
    if placed.bar and placed.bar.mod == mod then return placed.bar end
    for _, b in ipairs(placed.boxes) do
        if b.mod == mod then return b end
    end
end

-- The timeline's zone: the whole width, along the bottom edge.
function M.bar_zone()
    local tl = modules.timeline
    return { mod = tl, bar = true, x0 = 0, y0 = tl.zone_top(state.h, state.scale), x1 = state.w, y1 = state.h }
end

-- The row and the timeline's zone as they are now.
function M.current()
    local placed = M.place(modules.row(), state)
    placed.bar = M.bar_zone()
    return placed
end

return M
