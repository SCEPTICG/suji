-- The title above the row: one line, or the series in small capitals above
-- the episode (see set-title in main.lua). A background layer, not an
-- element of the row: its box ends where the right part of the row starts.

local M = {}

-- Sizes in px at scale 1.
local X, LIFT = 32, 68 -- left edge and baseline above the bottom edge
local MARGIN = 24      -- kept free before the right part of the row
local SIZE, TOP_SIZE, TOP_SPACING, TOP_LIFT = 20, 13, 1.5, 22

local width -- of the text last drawn, in px; nil before the first time

-- Counts the changes of that width, so whoever keeps a zone knows when it
-- is out of date without asking for it on every paint.
M.measured = 0

-- box.x1: where the right part of the row starts.
function M.render(ctx, box, v)
    local st, text, draw = ctx.state, ctx.text, ctx.draw
    local s = st.scale
    local x, y, max_w = X * s, st.h - LIFT * s, box.x1 - (X + MARGIN) * s
    local top, main
    if st.series and st.episode then top, main = text.upper(st.series), st.episode
    else main = st.episode or st.series or st.title or "" end
    local main_w = function(t) return ctx.text_width(t, SIZE, true) end
    main = text.fit(main, max_w, main_w)
    local was = width
    width = main ~= "" and main_w(main) or 0
    local out = draw.text(x, y, 1, main, ctx.style(SIZE, v, true))
    if top then
        local top_w = function(t) return ctx.text_width(t, TOP_SIZE, false, TOP_SPACING) end
        top = text.fit(top, max_w, top_w)
        width = math.max(width, top ~= "" and top_w(top) or 0)
        out = out .. "\n" .. draw.text(x, y - TOP_LIFT * s, 1, top, ctx.style(TOP_SIZE, 0.8 * v, false, TOP_SPACING))
    end
    if width ~= was then M.measured = M.measured + 1 end
    return out
end

-- The box the title takes for a window st and the row's right part
-- starting at right_x0: always as tall as two lines, series or not, so a
-- title that grows a line is already inside it; as wide as the text last
-- drawn (measured then, so this costs nothing), or all the room it has
-- before that.
function M.zone(st, right_x0)
    local s = st.scale
    local x0 = X * s
    local x1 = right_x0 - MARGIN * s
    if width then x1 = math.min(x1, x0 + width) end
    return { x0 = x0, x1 = x1, y0 = st.h - (LIFT + TOP_LIFT + TOP_SIZE) * s, y1 = st.h - LIFT * s }
end

return M
