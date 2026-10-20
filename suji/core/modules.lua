-- The modules: suji's own row elements, the timeline and the title, the
-- context (ctx) they get from the core, the shared property observers and
-- the safe calls. A module is a table of optional functions:
--
--   init(ctx)               once at start; the place to call ctx.watch
--   available(ctx)          false hides it and leaves no gap (default: shown)
--   width(ctx)              its width in the row, in px already scaled
--   render(ctx, box, v)     ASS text for its box; v is the visibility, 0..1
--   press(ctx, box, x, y)   button down on its zone; true captures the
--                           mouse until the button is released
--   move(ctx, box, x, y)    the cursor moved while it holds the mouse
--   release(ctx, commit)    the button went up; commit is false when the
--                           drag is dropped (file change, window left...)
--   wheel(ctx, dir)         wheel over its zone: 1 up, -1 down
--
-- box: { x0, y0, x1, y1, cy } in window px, cy the centre of the row.
-- The core only calls modules through M.call: one that fails or returns
-- nonsense is turned off (not drawn, no clicks), logged once, and loses
-- the mouse if it held it. Modules have no clock of their own: to repaint
-- they call ctx.request().

local msg = require "mp.msg"
local opts = require "core.options"
local state = require "core.state"
local draw = require "core.draw"
local icons = require "core.icons"
local text = require "core.text"
local painter = require "core.painter"
local controls = require "core.controls"

local M = {}

local MAX_ASS = 65536     -- bytes a module may draw
local MAX_WIDTH = 100000  -- px a module may take
local MAX_CONDITIONS = 64 -- properties watched for the controls option

-- What every module gets. visible and hover_time are set by main.
local ctx = {
    state = state, opts = opts, draw = draw, icons = icons, text = text, log = msg,
    measure = painter.measure, -- width of one ASS event: measure(ass, guess)
    request = painter.request, -- ask for a paint
    BUTTON = 44, ICON = 22,    -- clickable square of a button and its icon, at scale 1
    visible = function() return false end,  -- the controls are on screen
    hover_time = function() return nil end, -- time under the cursor on the timeline
}
M.ctx = ctx

-- Text style for draw.text at the current scale and font.
function ctx.style(size, opacity, bold, spacing)
    local s = state.scale
    return { font = state.font, size = size * s, opacity = opacity, scale = s,
             bold = bold, spacing = spacing and spacing * s }
end

-- Width in px of one line of text, measured by libass.
function ctx.text_width(t, size, bold, spacing)
    local ass = draw.text(0, 0, 7, t, ctx.style(size, 1, bold, spacing))
    return painter.measure(ass, text.len(t) * size * state.scale * 0.55)
end

-- An icon of core/icons.lua centred on (cx, cy); nil for an unknown name.
function ctx.icon(name, cx, cy, v)
    local shape, stroke = icons.shape(name, cx, cy, ctx.ICON * state.scale)
    return shape and draw.stroke(shape, stroke, v, state.scale)
end

-- Safe calls ---------------------------------------------------------------

-- Weak keys: the command buttons of an old controls option can go.
local dead = setmetatable({}, { __mode = "k" })
local names = setmetatable({}, { __mode = "k" })
local listeners = {}

-- fn(mod) runs when a module is turned off.
function M.on_failure(fn) listeners[#listeners + 1] = fn end

local function kill(mod, what, err)
    if dead[mod] then return end
    dead[mod] = true
    msg.error(("module %s failed in %s and was turned off: %s"):format(
        draw.printable(names[mod] or "?", 64), what, draw.printable(err, 300)))
    for _, fn in ipairs(listeners) do fn(mod) end
    painter.request()
end

local CHECK = {
    render = function(r) return type(r) == "string" and #r <= MAX_ASS end,
    width = function(r) return type(r) == "number" and r >= 0 and r <= MAX_WIDTH end, -- NaN fails
}

function M.alive(mod) return mod ~= nil and not dead[mod] end

-- True when the module is alive and has the function fname.
function M.takes(mod, fname) return M.alive(mod) and mod[fname] ~= nil end

-- mod[fname](...), protected. Returns its first result, or nil when the
-- module is off, has no such function or failed.
function M.call(mod, fname, ...)
    if not M.takes(mod, fname) then return nil end
    local ok, r = pcall(mod[fname], ...)
    if ok and CHECK[fname] and not CHECK[fname](r) then ok, r = false, "bad result (" .. type(r) .. ")" end
    if not ok then kill(mod, fname, r); return nil end
    return r
end

-- Shared observers -----------------------------------------------------------

local watched = {} -- prop .. " " .. kind -> { list = { { fn, owner } }, seen, value }
local owner        -- the module whose init is running

local function deliver(it, value, prop)
    local r
    if it.owner then
        if dead[it.owner] then return end
        local ok
        ok, r = pcall(it.fn, value)
        if not ok then kill(it.owner, "watch " .. prop, r); return end
    else
        r = it.fn(value)
    end
    if r == true and ctx.visible() then painter.request() end
end

-- fn(value) runs when the property changes, and at once if a value has
-- already arrived. One mp.observe_property per property and type, however
-- many ask for it. fn returning true asks for a paint if the controls are
-- on screen.
function M.watch(prop, kind, fn)
    local key = prop .. " " .. kind
    local w = watched[key]
    if not w then
        w = { list = {} }
        watched[key] = w
        mp.observe_property(prop, kind, function(_, value)
            w.seen, w.value = true, value
            for _, it in ipairs(w.list) do deliver(it, value, prop) end
        end)
    end
    local it = { fn = fn, owner = owner }
    w.list[#w.list + 1] = it
    if w.seen then deliver(it, w.value, prop) end
end
ctx.watch = M.watch

-- The registry -------------------------------------------------------------

local ROW = {
    pause = require "modules.pause",
    time = require "modules.time",
    volume = require "modules.volume",
    fullscreen = require "modules.fullscreen",
}
local command = require "modules.command"
M.timeline = require "modules.timeline" -- always there, not part of the row
M.title = require "modules.title"       -- background layer above the row

local function init(mod, name)
    names[mod] = name
    owner = mod
    M.call(mod, "init", ctx)
    owner = nil
end

-- Called once by main, after the core's own observers.
function M.init()
    init(M.timeline, "timeline")
    init(M.title, "title")
    for _, name in ipairs({ "pause", "time", "volume", "fullscreen" }) do init(ROW[name], name) end
end

-- The controls option --------------------------------------------------------

local items = {}       -- the option, resolved: { mod | space | gap, cond }
local values = {}      -- last value of each property the conditions name
local cond_props, n_props = {}, 0 -- properties watched for conditions
local shown = ""       -- which conditions held at the last check
local on_layout        -- fn() when the row changed because of a condition

local warned, n_warned = {}, 0
local function warn(line)
    if warned[line] then return end
    if n_warned >= 100 then warned, n_warned = {}, 0 end
    warned[line], n_warned = true, n_warned + 1
    msg.warn(line)
end

local function conditions()
    local t = {}
    for i, it in ipairs(items) do t[i] = (not it.cond or controls.eval(it.cond, values)) and "1" or "0" end
    return table.concat(t)
end

local function watch_condition(prop)
    if cond_props[prop] then return end
    if n_props >= MAX_CONDITIONS then
        warn(("controls: more than %d properties in conditions, '%s' counts as false")
            :format(MAX_CONDITIONS, draw.printable(prop, 64)))
        return
    end
    cond_props[prop], n_props = true, n_props + 1
    M.watch(prop, "native", function(v)
        values[prop] = v
        local now = conditions()
        if now ~= shown then
            shown = now
            if on_layout then on_layout() end
        end
    end)
end

function M.on_layout(fn) on_layout = fn end

-- Read the controls option again. The caller lays out the row afterwards.
function M.set_controls(s)
    local list, used = {}, {}
    for _, e in ipairs(controls.parse(s, ROW, warn)) do
        local it = { cond = e.cond, space = e.kind == "space", gap = e.kind == "gap" }
        if e.kind == "module" then
            if used[e.name] then
                warn(("controls: '%s' is listed twice, only the first one is shown"):format(e.name))
                it = nil
            else
                used[e.name], it.mod = true, ROW[e.name]
            end
        elseif e.kind == "command" then
            it.mod = command.new(e)
            names[it.mod] = "command:" .. e.icon
        end
        list[#list + 1] = it
    end
    items = list
    for _, prop in ipairs(controls.props(items)) do watch_condition(prop) end
    shown = conditions()
end

-- The elements of the row to lay out now, in order: { mod, width },
-- { gap = true } or { space = true }. Hidden and failed modules are left out.
function M.row()
    local out = {}
    for _, it in ipairs(items) do
        if not it.cond or controls.eval(it.cond, values) then
            if it.space or it.gap then
                out[#out + 1] = { space = it.space, gap = it.gap }
            elseif M.call(it.mod, "available", ctx) ~= false and M.alive(it.mod) then
                local w = M.call(it.mod, "width", ctx)
                if w and M.alive(it.mod) then out[#out + 1] = { mod = it.mod, width = w } end
            end
        end
    end
    return out
end

return M
