-- The title above the row: one line, or the series in small capitals above
-- the episode (see set-title in main.lua). A background layer, not an
-- element of the row: its box ends where the right part of the row starts.

local M = {}

-- Sizes in px at scale 1.
local X, LIFT = 32, 68 -- left edge and baseline above the bottom edge
local MARGIN = 24      -- kept free before the right part of the row
local SIZE, TOP_SIZE, TOP_SPACING, TOP_LIFT = 20, 13, 1.5, 22

-- box.x1: where the right part of the row starts.
function M.render(ctx, box, v)
    local st, text, draw = ctx.state, ctx.text, ctx.draw
    local s = st.scale
    local x, y, max_w = X * s, st.h - LIFT * s, box.x1 - (X + MARGIN) * s
    local top, main
    if st.series and st.episode then top, main = text.upper(st.series), st.episode
    else main = st.episode or st.series or st.title or "" end
    main = text.fit(main, max_w, function(t) return ctx.text_width(t, SIZE, true) end)
    local out = draw.text(x, y, 1, main, ctx.style(SIZE, v, true))
    if top then
        top = text.fit(top, max_w, function(t) return ctx.text_width(t, TOP_SIZE, false, TOP_SPACING) end)
        out = out .. "\n" .. draw.text(x, y - TOP_LIFT * s, 1, top, ctx.style(TOP_SIZE, 0.8 * v, false, TOP_SPACING))
    end
    return out
end

return M
