-- The title at the top left: one line, or the series in small grey capitals
-- above the episode in bold (see set-title in main.lua), with the name of
-- the episode in grey after it when there is one. A background layer, not
-- an element of the row: it comes and goes with the controls.

local M = {}

-- Sizes in px at scale 1.
local X, TOP = 32, 24  -- left edge (kept free on the right too) and top of the first line
local SIZE, TOP_SIZE, TOP_SPACING = 20, 13, 1.5
local TOP_LINE, LINE = 20, 26 -- from the series' top to the episode's; the episode's line
local NAME_GAP = 10    -- between the episode and its name
local TOP_DIM, NAME_DIM = 0.7, 0.6 -- the grey of the series and of the name: opacities

local width -- of the text last drawn, in px; nil before the first time

-- Counts the changes of that width, so whoever keeps a zone knows when it
-- is out of date without asking for it on every paint.
M.measured = 0

-- box.x1: the right edge of the window.
function M.render(ctx, box, v)
    local st, text, draw = ctx.state, ctx.text, ctx.draw
    local s = st.scale
    local x, y, max_w = X * s, TOP * s, box.x1 - 2 * X * s
    local top, main
    if st.series and st.episode then top, main = text.upper(st.series), st.episode
    else main = st.episode or st.series or st.title or "" end
    local main_w = function(t) return ctx.text_width(t, SIZE, true) end
    main = text.fit(main, max_w, main_w)
    local was = width
    width = main ~= "" and main_w(main) or 0
    local out = {}
    if top then
        local top_w = function(t) return ctx.text_width(t, TOP_SIZE, false, TOP_SPACING) end
        top = text.fit(top, max_w, top_w)
        out[1] = draw.text(x, y, 7, top, ctx.style(TOP_SIZE, TOP_DIM * v, false, TOP_SPACING))
        y = y + TOP_LINE * s
    end
    out[#out + 1] = draw.text(x, y, 7, main, ctx.style(SIZE, v, true))
    -- The name only goes with an episode, in the room it leaves.
    if st.episode and st.episode_name and main ~= "" then
        local name_w = function(t) return ctx.text_width(t, SIZE) end
        local nx = x + width + NAME_GAP * s
        local name = text.fit(st.episode_name, max_w - (nx - x), name_w)
        if name ~= "" then
            out[#out + 1] = draw.text(nx, y, 7, name, ctx.style(SIZE, NAME_DIM * v))
            width = nx - x + name_w(name)
        end
    end
    if top then width = math.max(width, top ~= "" and ctx.text_width(top, TOP_SIZE, false, TOP_SPACING) or 0) end
    if width ~= was then M.measured = M.measured + 1 end
    return table.concat(out, "\n")
end

-- The box the title takes in a window st: always as tall as two lines,
-- series or not, so a title that grows a line is already inside it; as
-- wide as the text last drawn (measured then, so this costs nothing), or
-- all the room it has before that.
function M.zone(st)
    local s = st.scale
    local x0 = X * s
    local x1 = st.w - X * s
    if width then x1 = math.min(x1, x0 + width) end
    return { x0 = x0, x1 = x1, y0 = TOP * s, y1 = (TOP + TOP_LINE + LINE) * s }
end

return M
