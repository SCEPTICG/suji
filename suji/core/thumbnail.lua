-- Thumbnails on the timeline, made by thumbfast, a separate script (see
-- the README). While the cursor is on the grown timeline, or dragging it,
-- suji asks thumbfast for the frame at the time under the cursor and says
-- where to put it: centred on the cursor, just above the bar, inside the
-- row's side margins. thumbfast draws the image itself, over suji's
-- overlay; suji draws the box around it, a panel like the menus', with
-- the time and the chapter of that moment under the image.
--
-- What thumbfast documents for scripts like this one:
--   script-message thumbfast-info <json>   its state, sent by thumbfast:
--       { width, height, disabled, available }; width and height are in
--       OSD px, with the HiDPI scale already in them
--   script-message-to thumbfast thumb <seconds> <x> <y>   show the frame,
--       its top left corner at (x, y)
--   script-message-to thumbfast clear      take it away
--
-- Nothing is sent before thumbfast has said it can make thumbnails, nor
-- with thumbnails=no. A message only goes out when the time or the place
-- changes, from the paint that draws the box: no timers.

local msg = require "mp.msg"
local utils = require "mp.utils"
local opts = require "core.options"
local state = require "core.state"
local draw = require "core.draw"
local text = require "core.text"
local painter = require "core.painter"
local modules = require "core.modules"
local layout = require "core.layout"
local menu = require "core.menu"
local time = require "modules.time"

local M = {}

-- Sizes in px at scale 1. The image keeps thumbfast's own size.
local LINE_H = 20   -- the line under the image
local SIZE = 13     -- its text
local SEP = " \194\183 " -- between the time and the chapter: " · "
local CHAPTER_DIM = 0.6  -- the chapter's opacity
local MAX_SIDE = 4096    -- px; a larger thumbnail is not believed
local MAX_JSON = 4096    -- bytes of thumbfast-info read
local MAX_CHAPTER = 200  -- characters kept from a chapter's title

-- From the last thumbfast-info, kept for every file after it; nil before
-- the first, as if there were no thumbfast.
local info     -- { width, height } while thumbfast can make thumbnails, else nil
local sent     -- the thumbnail asked for: { ts, x, y, box }, nil when none
local caption  -- the line under it, kept until the time or the width changes
local chapters -- chapter-list

-- Where the box goes for the cursor at cx, its bottom on top (the top of
-- the timeline's zone), for an image tw x th px. Centred on the cursor and
-- kept inside the row's side margins. Returns { ix, iy, x0, y0, x1, y1 }:
-- the image's top left corner in whole px (for thumbfast) and the panel.
-- nil when the box does not fit in the window.
function M.place(cx, tw, th, st, top)
    local s = st.scale
    local pad, margin = menu.BG_PAD * s, layout.SIDE * s
    local fw, fh = tw + 2 * pad, th + LINE_H * s + 2 * pad
    if fw > st.w - 2 * margin or fh > top then return nil end
    local ix = math.floor(math.max(margin, math.min(st.w - margin - fw, cx - fw / 2)) + pad + 0.5)
    local iy = math.floor(top - fh + pad)
    return { ix = ix, iy = iy, x0 = ix - pad, y0 = iy - pad, x1 = ix + tw + pad, y1 = iy + th + LINE_H * s + pad }
end

-- The title of the chapter playing at time t, made printable; nil when
-- there is none or it has no title.
function M.chapter_at(list, t)
    if type(list) ~= "table" then return nil end
    local best, title
    for _, c in ipairs(list) do
        local ct = type(c) == "table" and tonumber(c.time)
        if ct and ct <= t and (not best or ct >= best) then best, title = ct, c.title end
    end
    if type(title) ~= "string" or title == "" then return nil end
    return draw.printable(text.prefix(title, MAX_CHAPTER))
end

-- The line under the image: the time, and the chapter after it, cut to
-- fit avail px. { left, right }; right is nil without a chapter.
local function line(t, avail)
    local c = caption
    if c and c.t == t and c.avail == avail and c.font == state.font and c.chapters == chapters then return c end
    local d = state.has_timeline() and state.duration or 0
    local left = time.format_time(t, math.max(t, d) >= 3600)
    local right
    local name = M.chapter_at(chapters, t)
    if name then
        local function width(s) return modules.ctx.text_width(s, SIZE) end
        name = text.fit(name, avail - width(left .. SEP), width)
        if name ~= "" then right = SEP .. name end
    end
    caption = { t = t, avail = avail, font = state.font, chapters = chapters, left = left, right = right }
    return caption
end

-- Take the thumbnail away, if one was asked for.
function M.clear()
    if not sent then return end
    sent, caption = nil, nil
    mp.commandv("script-message-to", "thumbfast", "clear")
end

-- True while a thumbnail is on screen: the row's time shows the position
-- then, the time under the cursor is in the box.
function M.shown() return sent ~= nil end

-- Ask for the thumbnail at time t (seconds) with the cursor at x, or take
-- it away when t is nil, thumbfast cannot make one, thumbnails=no or a menu
-- is open. Called by every paint, before the row is drawn.
function M.update(t, x)
    local box = t and info and opts.thumbnails and not menu.is_open()
        and M.place(x, info.width, info.height, state, layout.bar_zone().y0)
    if not box then return M.clear() end
    local ts = ("%.3f"):format(t)
    local same = sent and sent.ts == ts and sent.x == box.ix and sent.y == box.iy
    sent = { ts = ts, t = t, x = box.ix, y = box.iy, box = box }
    if not same then
        mp.commandv("script-message-to", "thumbfast", "thumb", ts, tostring(box.ix), tostring(box.iy))
    end
end

-- ASS for the box around the thumbnail at visibility v, nil when none.
function M.render(v)
    if not sent then return nil end
    local b, s = sent.box, state.scale
    local pad = menu.BG_PAD * s
    local c = line(sent.t, b.x1 - b.x0 - 2 * pad)
    local parts = { { c.left, v } }
    if c.right then parts[2] = { c.right, CHAPTER_DIM * v } end
    return menu.panel(b.x0, b.y0, b.x1, b.y1, v) .. "\n" ..
        draw.text((b.x0 + b.x1) / 2, b.y1 - pad - LINE_H * s / 2, 5, parts, modules.ctx.style(SIZE, v))
end

-- thumbfast's state. Only a sane size counts, and only while it is not
-- disabled (a file it cannot read, a stream with network=no...).
local function set_info(data)
    local w = type(data) == "table" and tonumber(data.width)
    local h = type(data) == "table" and tonumber(data.height)
    local new
    if w and h and w >= 1 and w <= MAX_SIDE and h >= 1 and h <= MAX_SIDE and data.disabled ~= true then
        new = { width = math.floor(w), height = math.floor(h) }
    end
    if (new and new.width) == (info and info.width) and (new and new.height) == (info and info.height) then return end
    info = new
    if opts.debug then msg.info(new and ("thumbfast: %dx%d"):format(new.width, new.height) or "thumbfast: none") end
    painter.request() -- the next paint asks for it, or takes it away
end

mp.register_script_message("thumbfast-info", function(json)
    if type(json) ~= "string" or #json > MAX_JSON then return set_info(nil) end
    set_info(utils.parse_json(json))
end)

modules.watch("chapter-list", "native", function(c)
    chapters = c
    return sent ~= nil
end)

return M
