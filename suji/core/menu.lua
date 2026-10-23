-- The menu service: one menu at a time, opened upwards above the timeline,
-- in line with the button of the module that asked for it. Modules use it
-- through their ctx:
--
--   ctx.open_menu(menu, box)  open menu from the button in box (the
--                             module's box); the same menu again closes it
--   ctx.update_menu(menu)     replace the open menu of the same type, if
--                             it is this module's: no animation, same scroll
--                             (selected_index moves a cursor of the keys)
--   ctx.mark_menu(type, i, on) mark item i of this module's open menu of
--                             that type as active or not, without cleaning
--                             the whole menu again (cheap for long lists)
--   ctx.close_menu()          close this module's menu
--   ctx.menu_open()           true while this module's menu is open
--
-- and the module gets menu_closed(ctx) when its menu closes, whatever the
-- reason (a choice, a click outside, Esc, another menu, its button gone).
--
-- Other scripts open menus too, with messages (core/messages.lua): those
-- menus have no owner module. They come out of a button of the row and
-- follow it, by its name in the controls option when the option changes
-- (command: buttons are made again then); if it leaves the row, they move
-- to the middle.
--
-- A menu, with the names of the open-menu message (see docs/api.md):
--   { type, title?, items, selected_index?, keep_open? }
-- An item:
--   { title, hint?, icon?, value?, active?, selectable?, muted?, italic?,
--     bold?, separator?, keep_open?, align? }
-- value is the mpv command run on a choice: a list of strings goes to
-- mp.commandv, a string to mp.command. An item with no value and
-- selectable = false is a group header. Everything is checked and cut by
-- M.clean before it is kept; the texts of an item are made printable when
-- it is first drawn (a list can hold thousands), and escaped for ASS.
--
-- One more field, action, is only for suji's own modules: a function run
-- on a choice instead of value (to read the clipboard at that moment, for
-- example). M.clean keeps it only for a trusted caller, which ctx.open_menu
-- is; a menu that comes from another script as JSON is cleaned untrusted,
-- and JSON cannot hold a function anyway.
--
-- The type of the open menu, whoever opened it, is in the property
-- user-data/suji/menu/type, which is deleted when it closes.
--
-- No timers: the fade in and out is the clock-based animation of
-- core/animation.lua, painted while it runs, and the menu only repaints on
-- input or new data. The keys (Esc, Up, Down, Enter) are bound while a menu
-- is open and only then.

local msg = require "mp.msg"
local state = require "core.state"
local opts = require "core.options"
local draw = require "core.draw"
local text = require "core.text"
local icons = require "core.icons"
local animation = require "core.animation"
local painter = require "core.painter"
local modules = require "core.modules"
local layout = require "core.layout"

local unpack = table.unpack or unpack

local M = {}

-- Sizes in px at scale 1.
local ROW_H = 30     -- one item
local TITLE_H = 26   -- the menu's title above the items
local PAD = 14       -- text inside the menu's left and right edges
local GAP = 12       -- between the menu and the timeline's zone
local TOP = 24       -- kept free at the top of the window
local MIN_W, MAX_W = 180, 420
local SIZE, HINT_SIZE, TITLE_SIZE = 15, 13, 13
local ICON = 18      -- an item's icon
local MARK_W, MARK_H = 2, 14 -- the active mark
local WHEEL_STEP = 2 -- items per wheel step
local BG_OPACITY = 0.6 -- the black panel behind the menu
local RADIUS = 8     -- its corners
local BG_PAD = 6     -- the panel's room above and below the items
local TITLE_DIM = 0.3 -- the title's opacity while a menu covers it

-- What a menu may hold: longer texts are cut, more items are left out.
M.MAX_ITEMS = 50000
local MAX_TITLE, MAX_HINT, MAX_TYPE, MAX_ICON = 200, 64, 64, 32
local MAX_ARGS, MAX_ARG = 64, 8192
local ALIGN = { center = "center", right = "right" } -- left is the default
local TYPE_PROP = "user-data/suji/menu/type"

local cur          -- the menu on screen (see start), nil when none
local tween = animation.new(0.15)
local on_change    -- fn() when the bindings or the paint must be redone
local published    -- the type in TYPE_PROP, nil when it is not set

-- Cleaning -------------------------------------------------------------------

-- Outside text, at most the bytes of n characters (4 each); nil when
-- empty. Cut to n characters when drawn (see fitted): walking the
-- characters of every item of a long list would cost seconds.
local function cut(s, n)
    if type(s) ~= "string" or s == "" then return nil end
    return #s > 4 * n and s:sub(1, 4 * n) or s
end

-- A command for mp.command (a string) or mp.commandv (a list of strings),
-- or nil when it is not one or is too long.
function M.clean_value(v)
    if type(v) == "string" then return v ~= "" and #v <= MAX_ARG and v or nil end
    if type(v) ~= "table" or #v == 0 or #v > MAX_ARGS then return nil end
    local out = {}
    for i = 1, #v do
        if type(v[i]) ~= "string" or #v[i] > MAX_ARG then return nil end
        out[i] = v[i]
    end
    return out
end

local function clean_item(it, trusted)
    return {
        title = cut(it.title, MAX_TITLE) or "",
        hint = cut(it.hint, MAX_HINT),
        icon = type(it.icon) == "string" and #it.icon <= MAX_ICON and it.icon or nil,
        value = M.clean_value(it.value),
        action = trusted and type(it.action) == "function" and it.action or nil,
        active = it.active == true or (type(it.active) == "number" and it.active ~= 0),
        selectable = it.selectable ~= false,
        muted = it.muted == true, italic = it.italic == true, bold = it.bold == true,
        separator = it.separator == true, keep_open = it.keep_open == true,
        align = ALIGN[it.align],
    }
end

-- Rough width in px at scale 1, from the first items: no measuring, so a
-- long list costs nothing. Text that does not fit is cut when drawn.
local function estimate(m)
    local w, icon = 0, 0
    for i = 1, math.min(#m.items, 200) do
        local it = m.items[i]
        local n = text.len(it.title) * SIZE + (it.hint and text.len(it.hint) * HINT_SIZE + PAD / 0.55 or 0)
        w = math.max(w, n * 0.55)
        if it.icon then icon = ICON + 8 end
    end
    if m.title then w = math.max(w, text.len(m.title) * TITLE_SIZE * 0.55) end
    m.icons = icon > 0
    return math.max(MIN_W, math.min(MAX_W, w + icon + 2 * PAD + 2))
end

-- A menu as the service keeps it, or nil and the reason. trusted: the
-- caller is one of suji's modules, so items may carry an action. A menu
-- with no type has the type "". warn(text) gets the warnings (msg.warn
-- when nil).
function M.clean(def, trusted, warn)
    if type(def) ~= "table" then return nil, "not a table" end
    warn = warn or msg.warn
    local mtype = def.type == nil and "" or def.type
    if type(mtype) ~= "string" or #mtype > MAX_TYPE then return nil, "bad type" end
    if def.items ~= nil and type(def.items) ~= "table" then return nil, "items is not a list" end
    local src = def.items or {}
    local items, index = {}, {}
    local n = #src
    if n > M.MAX_ITEMS then
        warn(("menu %s: %d items, only the first %d are shown"):format(
            draw.printable(mtype), n, M.MAX_ITEMS))
        n = M.MAX_ITEMS
    end
    for i = 1, n do
        if type(src[i]) == "table" then
            items[#items + 1] = clean_item(src[i], trusted)
            index[i] = #items
        end
    end
    local title = cut(def.title, MAX_TITLE)
    title = title and draw.printable(text.prefix(title, MAX_TITLE))
    local m = { type = mtype, title = title, items = items, keep_open = def.keep_open == true }
    -- selected_index, else the first active item, else the first.
    local sel = tonumber(def.selected_index)
    m.selected = sel and index[math.floor(sel)]
    if not m.selected then
        for i, it in ipairs(items) do
            if it.active then m.selected = i; break end
        end
    end
    m.selected = m.selected or 1
    m.est = estimate(m)
    return m
end

-- Where things go ------------------------------------------------------------

-- The menu's place for its anchor (the button's box, or { center = true }:
-- the middle of the window) and the window now, its bottom above the
-- timeline's zone, so it never covers the bar:
-- { x0, x1, y0 (top, title included), list_top, y1 (bottom), rows, row_h }.
local function place(m, anchor)
    local s = state.scale
    local side = layout.SIDE * s
    local w = math.max(1, math.min(m.est * s, state.w - 2 * side))
    -- Aligned with the button; moved left when it would leave the window.
    local x0 = anchor.center and (state.w - w) / 2 or math.max(side, math.min(anchor.x0, state.w - side - w))
    local y1 = layout.bar_zone().y0 - GAP * s
    local row_h, title_h = ROW_H * s, m.title and TITLE_H * s or 0
    local fit = math.max(1, math.floor((y1 - TOP * s - title_h) / row_h))
    local rows = math.min(#m.items, fit)
    local list_top = y1 - rows * row_h
    return { x0 = x0, x1 = x0 + w, y0 = list_top - title_h, list_top = list_top, y1 = y1,
             rows = rows, row_h = row_h }
end

local function geometry() return place(cur.def, cur.anchor) end

local function clamp_scroll(g)
    cur.scroll = math.max(0, math.min(cur.scroll, #cur.def.items - g.rows))
end

-- Scroll so that item i is on screen: in the middle if it was not, or
-- with step, just enough (the keys move one item at a time).
local function show(i, g, step)
    if i <= cur.scroll then
        cur.scroll = step and i - 1 or i - math.ceil(g.rows / 2)
    elseif i > cur.scroll + g.rows then
        cur.scroll = step and i - g.rows or i - math.ceil(g.rows / 2)
    end
    clamp_scroll(g)
end

-- Index of the item under (x, y), or nil.
local function item_at(x, y)
    local g = geometry()
    if x < g.x0 or x >= g.x1 or y < g.list_top or y >= g.y1 then return nil end
    local i = cur.scroll + math.floor((y - g.list_top) / g.row_h) + 1
    return cur.def.items[i] and i or nil
end

-- Opening and closing ----------------------------------------------------------

function M.on_change(fn) on_change = fn end
local function changed() if on_change then on_change() end end

-- True while a menu is open (and not fading out); with owner, its own.
function M.is_open(owner)
    return cur ~= nil and not cur.closing and (owner == nil or cur.owner == owner)
end

local KEYS -- see below

local function bind_keys(on)
    for key, fn in pairs(KEYS) do
        local name = "suji-menu-" .. key:lower()
        if on then
            mp.add_forced_key_binding(key, name, fn, { repeatable = key == "UP" or key == "DOWN" })
        else
            mp.remove_key_binding(name)
        end
    end
end

-- The owner hears that its menu closed. If it failed meanwhile it is
-- still told, protected, so it can stop the watches it started. A menu
-- from a message has no owner.
local function tell_owner(owner)
    if not owner then return end
    if modules.alive(owner) then
        modules.call(owner, "menu_closed")
    elseif type(owner.menu_closed) == "function" then
        pcall(owner.menu_closed, modules.ctx_of(owner))
    end
end

-- Set or delete user-data/suji/menu/type when the open menu changed.
-- Deleted by setting nil: mpv 0.40 deletes with del_property too, but
-- then does not tell the observers.
local function publish()
    local t = M.is_open() and cur.def.type or nil
    if t == published then return end
    published = t
    mp.set_property_native(TYPE_PROP, t)
end

-- The open menu starts closing: it fades out, or goes at once when instant.
local function shut(instant)
    local m = cur
    if instant then cur = nil end
    if not m.closing then
        m.closing = true
        bind_keys(false)
        animation.set_target(tween, 0, mp.get_time())
        tell_owner(m.owner)
    end
end

function M.close(instant)
    if not cur then return end
    shut(instant)
    publish()
    changed()
end

local function copy(box) return { x0 = box.x0, y0 = box.y0, x1 = box.x1, y1 = box.y1 } end

-- Whether the menu's panel covers the title's box (cur.over_title). Only
-- when the menu opens, changes or moves, or the title's width changes,
-- never per frame; nil: to work out at the next paint.
local function cover()
    local g, pad = geometry(), BG_PAD * state.scale
    local t = modules.title.zone(state)
    cur.title_measured = modules.title.measured
    cur.over_title = t.x1 > t.x0 and g.x0 < t.x1 and g.x1 > t.x0 and g.y0 - pad < t.y1 and g.y1 + pad > t.y0
end

-- The title's opacity, 0..1: down to TITLE_DIM while an open menu covers
-- it, with the menu's own fade in and out.
function M.title_opacity(now)
    if not cur then return 1 end
    if cur.title_measured ~= modules.title.measured then cur.over_title = nil end -- a new title
    if cur.over_title == nil then cover() end
    if not cur.over_title then return 1 end
    return 1 - (1 - TITLE_DIM) * animation.value(tween, now)
end

-- Put the clean menu m on screen for owner (nil: a message's), from
-- anchor (see place), following the row's module follow when it moves.
local function start(owner, m, follow, anchor)
    if cur then shut(true) end -- one menu at a time
    cur = { def = m, owner = owner, follow = follow, anchor = anchor, scroll = 0,
            name = not owner and follow and modules.name_of(follow) or nil }
    show(m.selected, geometry())
    cover()
    tween = animation.new(0.15)
    animation.set_target(tween, 1, mp.get_time())
    bind_keys(true)
    publish()
    changed()
end

-- The open menu shows m instead: at once, with the same scroll and cursor
-- when they still fit. A cursor that follows the mouse goes to the item
-- under it now (another list, or the menu moved).
local function replace(m)
    cur.def = m
    if cur.cursor and not m.items[cur.cursor] then cur.cursor = nil end
    clamp_scroll(geometry())
    cover() -- its size may have changed
    if not cur.by_keys and cur.px then M.pointer(cur.px, cur.py) end
    painter.request()
    return true
end

-- Open def for owner from the button in box. Opening the menu that is
-- open already closes it. Returns true when a menu was opened.
function M.open(owner, def, box)
    if type(box) ~= "table" or type(box.x0) ~= "number" or type(box.y0) ~= "number" then return false end
    if M.is_open(owner) and type(def) == "table" and def.type == cur.def.type then
        M.close()
        return false
    end
    local m, why = M.clean(def, true)
    if not m then
        msg.warn("menu not opened: " .. why)
        return false
    end
    start(owner, m, owner, copy(box))
    return true
end

-- New data for owner's open menu of the same type. With selected_index (a
-- new list), a cursor the keys moved goes to that item.
function M.update(owner, def)
    if not M.is_open(owner) or type(def) ~= "table" or def.type ~= cur.def.type then return false end
    local m = M.clean(def, true)
    if not m then return false end
    replace(m)
    if def.selected_index ~= nil and cur.by_keys and m.items[m.selected] then
        cur.cursor = m.selected
        show(cur.cursor, geometry(), true)
    end
    return true
end

-- The type of the open menu, or nil.
function M.open_type() return M.is_open() and cur.def.type or nil end

-- True while a menu that a message opened is open.
function M.message_open() return M.is_open() and not cur.owner end

-- Messages (core/messages.lua): def is untrusted, warn(text) gets what is
-- wrong with it.

-- Open def from box, a box of the row (the menu follows its module), or
-- centred when box is nil. A menu of the same type opened by a message is
-- replaced in place instead. True when it is on screen.
function M.open_message(def, box, warn)
    local m, why = M.clean(def, false, warn)
    if not m then
        warn("open-menu: " .. why)
        return false
    end
    if M.is_open() and not cur.owner and m.type == cur.def.type then return replace(m) end
    start(nil, m, box and box.mod, box and copy(box) or { center = true })
    return true
end

-- New data for the open menu of the same type, if a message opened it;
-- else nothing happens (no menu opens, suji's own menus are left alone).
function M.update_message(def, warn)
    if not M.is_open() or cur.owner or type(def) ~= "table" or (def.type == nil and "" or def.type) ~= cur.def.type then
        return false
    end
    local m, why = M.clean(def, false, warn)
    if not m then
        warn("update-menu: " .. why)
        return false
    end
    return replace(m)
end

-- Item i of owner's open menu of type mtype becomes active (on) or not.
function M.mark(owner, mtype, i, on)
    local it = M.is_open(owner) and mtype == cur.def.type and cur.def.items[i]
    if not it then return false end
    it.active = on == true
    painter.request()
    return true
end

modules.bind("open_menu", M.open)
modules.bind("mark_menu", M.mark)
modules.bind("update_menu", M.update)
modules.bind("close_menu", function(owner) if M.is_open(owner) then M.close() end end)
modules.bind("menu_open", M.is_open)

-- The row was laid out again: the menu follows its button. When the
-- button is gone (hidden, failed, or out of the controls option), a
-- module's menu closes and a message's moves to the middle.
function M.on_layout()
    if not M.is_open() then return end
    if cur.follow then
        local placed = layout.current()
        local box = layout.find(placed, cur.follow) or cur.name and layout.named(placed, cur.name)
        if box then
            cur.follow, cur.anchor = box.mod, copy(box)
        elseif cur.owner then
            return M.close()
        else
            cur.follow, cur.anchor = nil, { center = true }
        end
    end
    cover()
end

-- A new file: a menu from a message was about the old one, so it closes.
-- suji's own menus stay and follow the new file (see menu_button).
mp.register_event("end-file", function()
    if M.is_open() and not cur.owner then M.close() end
end)

modules.on_failure(function(mod)
    if not cur then return end
    if cur.owner == mod then
        M.close()
    elseif cur.follow == mod then
        -- Not laid out from here (this runs inside a module call).
        cur.follow, cur.anchor, cur.over_title = nil, { center = true }, nil
    end
end)

-- Choosing -----------------------------------------------------------------------

local function run(m, it)
    if it.action then
        local ok, err = pcall(it.action)
        if not ok then msg.error(("menu %s: action failed: %s"):format(draw.printable(m.type), draw.printable(err, 300))) end
    elseif it.value then
        local ok, err
        if type(it.value) == "string" then ok, err = mp.command(it.value) else ok, err = mp.commandv(unpack(it.value)) end
        if ok == nil and err then
            msg.warn(("menu %s: command failed: %s"):format(draw.printable(m.type), draw.printable(err, 300)))
        end
    end
end

-- The item runs first, then the menu closes: a script hears the choice
-- before the type goes. Unless the item opened another menu meanwhile.
local function choose(i)
    local it = i and cur.def.items[i]
    if not it or not it.selectable then return end
    local m, def = cur, cur.def
    run(def, it)
    if cur == m and not m.closing and not (def.keep_open or it.keep_open) then M.close() end
end

-- The next item that can be chosen from i in direction d, or i.
local function step(i, d)
    local items = cur.def.items
    local j = i + d
    while items[j] and not items[j].selectable do j = j + d end
    return items[j] and j or i
end

local function move(d)
    return function()
        if not M.is_open() or #cur.def.items == 0 then return end
        local items = cur.def.items
        local i = cur.cursor and step(cur.cursor, d) or cur.def.selected
        -- Never on an item that cannot be chosen: the next one that can,
        -- that way or else the other; none, and the cursor stays put.
        if not items[i].selectable then i = step(i, d) end
        if not items[i].selectable then i = step(i, -d) end
        if not items[i].selectable then return end
        cur.cursor, cur.by_keys = i, true
        show(i, geometry(), true)
        painter.request()
    end
end

KEYS = {
    ESC = function() M.close() end,
    UP = move(-1),
    DOWN = move(1),
    ENTER = function() if M.is_open() then choose(cur.cursor or cur.def.selected) end end,
}
KEYS.KP_ENTER = KEYS.ENTER

-- Mouse ------------------------------------------------------------------------

-- True when (x, y) is on the open menu's panel, its title included.
function M.contains(x, y)
    if not M.is_open() or not x then return false end
    local g, pad = geometry(), BG_PAD * state.scale
    return x >= g.x0 and x < g.x1 and y >= g.y0 - pad and y < g.y1 + pad
end

-- The cursor moved (x nil: it left the window). The item under it is
-- highlighted; off the menu the highlight goes, unless the keys set it.
function M.pointer(x, y)
    if not M.is_open() then return end
    cur.px, cur.py = x, y
    local i = x and item_at(x, y)
    if i then
        cur.cursor, cur.by_keys = cur.def.items[i].selectable and i or nil, false
    elseif not cur.by_keys then
        cur.cursor = nil
    end
end

-- The item of the open menu under (x, y): its index and title, or nil.
function M.item_under(x, y)
    local i = M.is_open() and item_at(x, y)
    if i then return i, cur.def.items[i].title end
end

-- A click on the menu: on an item it is a choice.
function M.press(x, y)
    if M.is_open() then choose(item_at(x, y)) end
end

function M.wheel(dir)
    if not M.is_open() then return end
    cur.scroll = cur.scroll - dir * WHEEL_STEP
    clamp_scroll(geometry())
    M.pointer(cur.px, cur.py)
    painter.request()
end

-- Drawing ----------------------------------------------------------------------

local function style(size, opacity, bold, italic)
    local t = modules.ctx.style(size, opacity, bold)
    t.italic = italic
    return t
end

-- The title and hint of item it, printable and cut to the width avail,
-- kept until the width or the font changes: only the items on screen are
-- ever cleaned and measured. The hint takes what the title leaves, and at
-- least 45% of the width when both are long.
local function fitted(it, avail)
    local f = it.fit
    if f and f.avail == avail and f.font == state.font then return f end
    if not it.printable then
        it.title = draw.printable(text.prefix(it.title, MAX_TITLE))
        it.hint = it.hint and draw.printable(text.prefix(it.hint, MAX_HINT))
        it.printable = true
    end
    local tw, gap = modules.ctx.text_width, PAD * state.scale
    local function title_w(t) return tw(t, SIZE, it.bold) end
    local hint = it.hint and text.fit(it.hint, math.max(avail * 0.45, avail - title_w(it.title) - gap),
        function(t) return tw(t, HINT_SIZE) end)
    local used = hint and hint ~= "" and tw(hint, HINT_SIZE) + gap or 0
    f = { avail = avail, font = state.font, hint = hint, used = used, title = text.fit(it.title, avail - used, title_w) }
    it.fit = f
    return f
end

-- A small chevron pointing up (d = -1) or down (d = 1) at (cx, cy).
local function chevron(cx, cy, d, p, s)
    local dx, dy = 5 * s, 2.5 * s * d
    return draw.stroke({ { cx - dx, cy - dy, cx, cy + dy, cx + dx, cy - dy } }, 1.5 * s, 0.6 * p, s)
end

local function draw_item(out, it, i, y0, g, p, s)
    local cy = y0 + g.row_h / 2
    if i == cur.cursor and it.selectable then
        -- Inset and rounded, so it stays inside the panel's corners.
        out[#out + 1] = draw.round_rect(g.x0 + 3 * s, y0, g.x1 - 3 * s, y0 + g.row_h, 4 * s, { opacity = 0.1 * p })
    end
    if it.active then
        -- A thin upright line in the accent, with the dark halo of the bar.
        local mx0, mx1 = g.x0 + 4 * s, g.x0 + (4 + MARK_W) * s
        local my0, my1 = cy - MARK_H * s / 2, cy + MARK_H * s / 2
        out[#out + 1] = draw.rect(mx0 - s, my0 - s, mx1 + s, my1 + s, { color = "&H000000&", opacity = 0.45 * p, blur = s })
        out[#out + 1] = draw.rect(mx0, my0, mx1, my1, { color = draw.color(opts.accent) or "&HFFFFFF&", opacity = p })
    end
    local op = ((it.muted or not it.selectable) and 0.5 or 1) * p
    local x = g.x0 + PAD * s
    if cur.def.icons then
        local shape, width = icons.shape(it.icon or "", x + ICON * s / 2, cy, ICON * s)
        if shape then out[#out + 1] = draw.stroke(shape, width, op, s) end
        x = x + (ICON + 8) * s
    end
    local f = fitted(it, g.x1 - PAD * s - x)
    if f.title ~= "" then
        -- Aligned in the room the hint leaves.
        local right, an = g.x1 - PAD * s - f.used, 4
        if it.align == "center" then x, an = (x + right) / 2, 5 elseif it.align == "right" then x, an = right, 6 end
        out[#out + 1] = draw.text(x, cy, an, f.title, style(SIZE, op, it.bold, it.italic))
    end
    if f.hint and f.hint ~= "" then
        out[#out + 1] = draw.text(g.x1 - PAD * s, cy, 6, f.hint, style(HINT_SIZE, 0.6 * op))
    end
    if it.separator then
        local t = math.max(1, math.floor(s + 0.5))
        out[#out + 1] = draw.rect(g.x0, y0 + g.row_h - t, g.x1, y0 + g.row_h, { opacity = 0.25 * p })
    end
end

-- A black, see-through panel with round corners, behind everything: the
-- menu's, and the thumbnail's box (core/thumbnail.lua). p: its opacity.
M.BG_PAD = BG_PAD
function M.panel(x0, y0, x1, y1, p)
    return draw.round_rect(x0, y0, x1, y1, RADIUS * state.scale, { color = "&H000000&", opacity = BG_OPACITY * p })
end

-- ASS for the menu at time now (nil when there is none) and whether it is
-- still animating. Only the items on screen are drawn.
function M.render(now)
    if not cur then return nil, false end
    local p, running = animation.value(tween, now), animation.running(tween, now)
    if cur.closing and not running then
        cur = nil
        return nil, false
    end
    if p <= 0 then return nil, running end
    local s, g = state.scale, geometry()
    clamp_scroll(g)
    local out, items = {}, cur.def.items
    out[1] = M.panel(g.x0, g.y0 - BG_PAD * s, g.x1, g.y1 + BG_PAD * s, p)
    if cur.def.title then
        local t = text.fit(cur.def.title, g.x1 - g.x0 - 2 * PAD * s,
            function(t) return modules.ctx.text_width(t, TITLE_SIZE) end)
        out[#out + 1] = draw.text(g.x0 + PAD * s, g.y0 + TITLE_H * s / 2, 4, t, style(TITLE_SIZE, 0.6 * p))
    end
    for k = 1, g.rows do
        local i = cur.scroll + k
        draw_item(out, items[i], i, g.list_top + (k - 1) * g.row_h, g, p, s)
    end
    -- More above or below: a faint chevron at that edge.
    local cx = (g.x0 + g.x1) / 2
    if cur.scroll > 0 then out[#out + 1] = chevron(cx, g.list_top - 4 * s, -1, p, s) end
    if cur.scroll + g.rows < #items then out[#out + 1] = chevron(cx, g.y1 + 3 * s, 1, p, s) end
    local ass = table.concat(out, "\n")
    if p < 1 then
        -- Unfolding upwards from the timeline: a clip that grows with p.
        local bottom = g.y1 + GAP * s
        local top = bottom - (bottom - g.y0 + 8 * s) * p
        local clip = ("{\\clip(%d,%d,%d,%d)}"):format(math.floor(g.x0 - 8 * s), math.floor(top),
            math.ceil(g.x1 + 8 * s), math.ceil(bottom))
        ass = clip .. ass:gsub("\n", "\n" .. clip)
    end
    return ass, running
end

return M
