-- Action buttons: a text button above the row, on the right, that another
-- script shows for as long as it needs it ("Skip opening ›"), with the
-- show-action and hide-action messages (core/messages.lua, docs/api.md).
-- A click runs its command; the button stays until the script hides it.
--
-- They are not modules of the row: they are on screen while the row is
-- hidden, so a skip needs no mouse move, and they go while a menu is open
-- and come back when it closes. At most MAX_SHOWN at a time, right to left
-- in the order they came; the others wait for a free place. A new file or
-- turning suji off removes them all: they were about the old file.
--
-- No timers: they fade in and out with the clock-based animation of
-- core/animation.lua, like the menus, and only repaint on input or new data.

local msg = require "mp.msg"
local state = require "core.state"
local opts = require "core.options"
local draw = require "core.draw"
local text = require "core.text"
local animation = require "core.animation"
local modules = require "core.modules"
local layout = require "core.layout"
local menu = require "core.menu"

local unpack = table.unpack or unpack

local M = {}

M.MAX = 16       -- ids kept; more are refused, so a script cannot fill the memory
M.MAX_SHOWN = 4  -- on screen at a time
M.MAX_TEXT = 64  -- bytes of a text

-- Sizes in px at scale 1. The look is the menus' (core/menu.lua).
local H = 36         -- a button's height
local PAD = 14       -- text inside its left and right edges
local GAP = 12       -- between the buttons and the row
local SPACE = 8      -- between two buttons
local SIZE = 15
local BG_OPACITY = 0.6
local RADIUS = 8

local list = {}      -- { id, text, command, tween }, in the order they came
local ghosts = {}    -- hidden ones fading out where they were: { box, text, tween }
local group = animation.new(0.15, 1) -- all of them: 0 while a menu is open
local placed         -- the boxes of the shown ones (see place), nil: to work out
local key            -- window, scale and font placed was worked out for
local px, py         -- the cursor, nil when it is not in the window
local on_change      -- fn() when the bindings or the paint must be redone

function M.on_change(fn) on_change = fn end
local function changed()
    placed = nil
    if on_change then on_change() end
end

local function find(id)
    for i, a in ipairs(list) do if a.id == id then return i end end
end

local function same(c1, c2)
    if type(c1) ~= "table" or type(c2) ~= "table" then return c1 == c2 end
    if #c1 ~= #c2 then return false end
    for i = 1, #c1 do if c1[i] ~= c2[i] then return false end end
    return true
end

-- The boxes of the buttons on screen, { a, x0, y0, x1, y1, cy, text },
-- from the right margin leftwards, their bottom GAP above the top of the
-- row (the timeline's zone when the row is empty): the same place whether
-- the controls are shown or hidden. A button that would leave the window
-- on the left waits like the ones over MAX_SHOWN; the first one is cut.
-- Worked out again only when the buttons, the row, the window, the scale
-- or the font changed.
local function place()
    local k = ("%s %s %s %s"):format(state.w, state.h, state.scale, state.font)
    if placed and key == k then return placed end
    local boxes = {}
    placed, key = boxes, k
    if #list == 0 or state.w <= 0 or state.h <= 0 then return boxes end
    local s, now = state.scale, mp.get_time()
    local row = layout.current()
    local y1 = (row.boxes[1] or row.bar).y0 - GAP * s
    local y0 = y1 - H * s
    local left, x1 = layout.SIDE * s, state.w - layout.SIDE * s
    local function width(t) return modules.ctx.text_width(t, SIZE) end
    for _, a in ipairs(list) do
        if #boxes == M.MAX_SHOWN then break end
        local t = a.text
        if #boxes == 0 then t = text.fit(t, x1 - left - 2 * PAD * s, width) end
        local x0 = x1 - width(t) - 2 * PAD * s
        if #boxes > 0 and x0 < left then break end
        boxes[#boxes + 1] = { a = a, x0 = x0, y0 = y0, x1 = x1, y1 = y1, cy = (y0 + y1) / 2, text = t }
        animation.set_target(a.tween, 1, now) -- fades in the first time it is shown
        x1 = x0 - SPACE * s
    end
    return boxes
end

local function inside(b, x, y) return x >= b.x0 and x < b.x1 and y >= b.y0 and y < b.y1 end

-- True while the buttons can be seen and clicked: suji is on and no menu
-- is open.
local function usable() return opts.enabled and not menu.is_open() end

-- Show button id with the clean fields f: { text, command } (see
-- core/messages.lua), or change it. Returns true when something changed,
-- nil when nothing did, or false and the reason when there are M.MAX
-- buttons already.
function M.set(id, f)
    local i = find(id)
    if i then
        local a = list[i]
        if a.text == f.text and same(a.command, f.command) then return nil end
        a.text, a.command = f.text, f.command
    else
        if #list >= M.MAX then return false, ("more than %d action buttons"):format(M.MAX) end
        list[#list + 1] = { id = id, text = f.text, command = f.command, tween = animation.new(0.15) }
    end
    changed()
    return true
end

-- Hide button id; with no id, all of them. instant: no fade (suji is
-- being turned off). Those on screen fade out where they were.
function M.hide(id, instant)
    if instant then ghosts = {} end
    local now, shown = mp.get_time(), {}
    if not instant and usable() then
        for _, b in ipairs(place()) do shown[b.a] = b end
    end
    local keep = {}
    for _, a in ipairs(list) do
        if id == nil or a.id == id then
            local b = shown[a]
            if b then
                animation.set_target(a.tween, 0, now)
                ghosts[#ghosts + 1] = { box = b, text = b.text, tween = a.tween }
            end
        else
            keep[#keep + 1] = a
        end
    end
    if #keep == #list then return end
    list = keep
    changed()
end

-- The button shown at (x, y), or nil.
function M.at(x, y)
    if not x or not usable() then return nil end
    for _, b in ipairs(place()) do
        if inside(b, x, y) then return b.a end
    end
end

-- A click on button a: its command runs.
function M.press(a)
    local c = a.command
    if not c then return end
    local ok, err
    if type(c) == "string" then ok, err = mp.command(c) else ok, err = mp.commandv(unpack(c)) end
    if ok == nil and err then
        msg.warn(("action %s: command failed: %s"):format(a.id, draw.printable(err, 300)))
    end
end

-- The cursor moved (x nil: it left the window): the button under it is lit.
function M.pointer(x, y) px, py = x, y end

-- The row, the window or the scale changed.
function M.on_layout() placed = nil end

-- ASS for the buttons at time now and whether they are still animating.
function M.render(now)
    animation.set_target(group, menu.is_open() and 0 or 1, now)
    if #list == 0 and #ghosts == 0 then return nil, false end
    local g, running = animation.value(group, now), animation.running(group, now)
    local s, out = state.scale, {}
    local function button(b, p, lit)
        if p <= 0 then return end
        out[#out + 1] = draw.round_rect(b.x0, b.y0, b.x1, b.y1, RADIUS * s,
            { color = "&H000000&", opacity = BG_OPACITY * p })
        if lit then
            out[#out + 1] = draw.round_rect(b.x0 + 3 * s, b.y0 + 3 * s, b.x1 - 3 * s, b.y1 - 3 * s, 4 * s,
                { opacity = 0.1 * p })
        end
        out[#out + 1] = draw.text((b.x0 + b.x1) / 2, b.cy, 5, b.text, modules.ctx.style(SIZE, p))
    end
    local left = {}
    for _, gh in ipairs(ghosts) do
        if animation.running(gh.tween, now) then
            left[#left + 1] = gh
            running = true
            button(gh.box, g * animation.value(gh.tween, now), false)
        end
    end
    ghosts = left
    for _, b in ipairs(place()) do
        running = running or animation.running(b.a.tween, now)
        button(b, g * animation.value(b.a.tween, now), px and usable() and inside(b, px, py))
    end
    return table.concat(out, "\n"), running
end

-- A new file: the buttons were about the old one.
mp.register_event("end-file", function() M.hide() end)

return M
