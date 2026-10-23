-- The modules: suji's own row elements, the timeline and the title, the
-- context (ctx) they get from the core, the shared property observers and
-- the safe calls. A module is a table of optional functions:
--
--   init(ctx)               once at start; the place to call ctx.watch
--   available(ctx)          false hides it and leaves no gap (default: shown)
--   width(ctx)              its width in the row, in px already scaled
--   render(ctx, box, v)     ASS text for its box (nil: nothing); v is the
--                           visibility, 0..1
--   press(ctx, box, x, y)   button down on its zone; true captures the
--                           mouse until the button is released
--   move(ctx, box, x, y)    the cursor moved while it holds the mouse
--   release(ctx, commit)    the button went up; commit is false when the
--                           drag is dropped (file change, window left...)
--   wheel(ctx, dir)         wheel over its zone: 1 up, -1 down
--   hover(ctx, on)          the cursor came onto its zone (true) or left
--                           it (false)
--   menu_closed(ctx)        the menu it opened closed (see core/menu.lua)
--
-- and one field: once = true makes a double click on it one press (the
-- second click of it runs nothing, as on an action button; core/mouse.lua).
--
-- box: { x0, y0, x1, y1, cy } in window px, cy the centre of the row.
-- The core only calls modules through M.call, which gives each module its
-- own ctx: one that fails or returns nonsense is turned off (not drawn, no
-- clicks), logged once, and lets go of the mouse if it held it. Modules
-- have no clock of their own: to repaint they call ctx.request(), and
-- ctx.relayout() when their width or available() changed.

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

local on_layout -- fn() to lay out the row and its zones again (set by main)

-- What every module gets. visible and hover_time are set by main.
local ctx = {
    state = state, opts = opts, draw = draw, icons = icons, text = text, log = msg,
    measure = painter.measure, -- width of one ASS event: measure(ass, guess)
    request = painter.request, -- ask for a paint
    BUTTON = 44, ICON = 22,    -- clickable square of a button and its icon, at scale 1
    visible = function() return false end,  -- the controls are on screen
    hover_time = function() return nil end, -- time under the cursor on the timeline
}
M.ctx = ctx -- the core's own; modules get theirs from M.ctx_of

function ctx.relayout() if on_layout then on_layout() end end

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

-- A short text, small and bold, in the top right corner of a button's box:
-- the badge of set-button, the speed away from 1x.
function ctx.badge(t, box, v)
    local s = state.scale
    return draw.text(box.x1 - 3 * s, box.cy - 11 * s, 6, t, ctx.style(10, v, true))
end

-- Safe calls ---------------------------------------------------------------

-- Weak keys: the command buttons of an old controls option can go.
local dead = setmetatable({}, { __mode = "k" })
local names = setmetatable({}, { __mode = "k" })
-- Weak values too: a ctx refers to its module, and with weak keys alone
-- Lua 5.1 would keep both forever. A ctx nobody holds is made again.
local contexts = setmetatable({}, { __mode = "kv" })
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

local watched -- see below
local deliver

-- Turn a module that failed on again (main does it for the timeline when
-- a new file starts: suji is no use without it). Its watches get the last
-- value of each property again: while off, it missed the changes.
function M.revive(mod)
    if not dead[mod] then return end
    dead[mod] = nil
    -- A delivery may watch or unwatch: walk copies, not the live tables.
    local mine = {}
    for _, w in pairs(watched) do
        if w.seen then
            for _, it in ipairs(w.list) do if it.owner == mod then mine[#mine + 1] = { it, w } end end
        end
    end
    for _, p in ipairs(mine) do
        local it, w = p[1], p[2]
        if not it.gone then deliver(it, w.value) end
    end
end

-- A reason when the result is not usable, nil when it is.
local CHECK = {
    render = function(r)
        if type(r) ~= "string" then return "bad result (" .. type(r) .. ")" end
        if #r > MAX_ASS then return ("render too large (%d bytes)"):format(#r) end
    end,
    width = function(r)
        if type(r) ~= "number" or not (r >= 0 and r <= MAX_WIDTH) then return "bad width (" .. tostring(r) .. ")" end
    end,
}

function M.alive(mod) return mod ~= nil and not dead[mod] end

-- The name of a module of the row as the controls option writes it
-- ("more", "command:x", "button:name"), or nil.
function M.name_of(mod) return names[mod] end

-- True when the module is alive and has the function fname.
function M.takes(mod, fname) return M.alive(mod) and mod[fname] ~= nil end

-- mod[fname](ctx, ...), protected, with the module's own ctx. Returns its
-- first result, or nil when the module is off, has no such function or
-- failed. A render that returns nil draws nothing.
function M.call(mod, fname, ...)
    if not M.takes(mod, fname) then return nil end
    local ok, r = pcall(mod[fname], M.ctx_of(mod), ...)
    if ok and fname == "render" and r == nil then r = "" end
    local bad = ok and CHECK[fname] and CHECK[fname](r)
    if bad then ok, r = false, bad end
    if not ok then kill(mod, fname, r); return nil end
    return r
end

-- Shared observers -----------------------------------------------------------

watched = {} -- prop .. " " .. kind -> { list = { handle }, seen, value, observer }

-- Every delivery is protected: a module's failure turns it off, a core
-- observer's is logged once; the others still get the value.
function deliver(it, value)
    if it.owner and dead[it.owner] then return end
    local ok, r = pcall(it.fn, value)
    if not ok then
        if it.owner then kill(it.owner, "watch " .. it.prop, r)
        elseif not it.failed then
            it.failed = true
            msg.error(("observer of %s failed: %s"):format(draw.printable(it.prop, 64), draw.printable(r, 300)))
        end
    elseif r == true and ctx.visible() then
        painter.request()
    end
end

-- fn(value) runs when the property changes, and at once if a value has
-- already arrived. One mp.observe_property per property and type, however
-- many ask for it. fn returning true asks for a paint if the controls are
-- on screen. owner: the module it belongs to (ctx.watch sets it). Returns
-- a handle for M.unwatch.
function M.watch(prop, kind, fn, owner)
    local key = prop .. " " .. kind
    local w = watched[key]
    if not w then
        w = { list = {} }
        w.observer = function(_, value)
            w.seen, w.value = true, value
            for _, it in ipairs(w.list) do deliver(it, value) end
        end
        watched[key] = w
        mp.observe_property(prop, kind, w.observer)
    end
    local it = { fn = fn, owner = owner, prop = prop, key = key }
    w.list[#w.list + 1] = it
    if w.seen then deliver(it, w.value) end
    return it
end

-- Stop a watch. The last one of a property stops observing it.
function M.unwatch(it)
    it.gone = true
    local w = watched[it.key]
    if not w then return end
    local list = {} -- a new list: a delivery in progress keeps the old one
    for _, other in ipairs(w.list) do if other ~= it then list[#list + 1] = other end end
    w.list = list
    if #list == 0 then
        watched[it.key] = nil
        mp.unobserve_property(w.observer)
    end
end
ctx.unwatch = M.unwatch

-- Functions of the ctx tied to the module that calls them: name -> fn(mod, ...).
local bound = {}

-- Give every module's ctx a function name that calls fn(mod, ...) (the
-- menu service adds ctx.open_menu and its friends this way).
function M.bind(name, fn) bound[name] = fn end

-- The ctx of module mod: the core's, with watch and unwatch tied to mod.
function M.ctx_of(mod)
    local c = contexts[mod]
    if not c then
        c = setmetatable({
            watch = function(prop, kind, fn) return M.watch(prop, kind, fn, mod) end,
            -- Only the module's own watches.
            unwatch = function(it) if type(it) == "table" and it.owner == mod then M.unwatch(it) end end,
        }, { __index = function(t, k)
            local fn = bound[k]
            if not fn then return ctx[k] end
            local f = function(...) return fn(mod, ...) end
            rawset(t, k, f)
            return f
        end })
        contexts[mod] = c
    end
    return c
end

-- The registry -------------------------------------------------------------

local skip = require "modules.skip"
local ROW = {
    pause = require "modules.pause",
    prev = skip.new(-1),
    next = skip.new(1),
    time = require "modules.time",
    volume = require "modules.volume",
    fullscreen = require "modules.fullscreen",
    subtitles = require "modules.subtitles",
    audio = require "modules.audio",
    playlist = require "modules.playlist",
    speed = require "modules.speed",
    more = require "modules.more",
}
local command = require "modules.command"
local button = require "modules.button"
M.timeline = require "modules.timeline" -- always there, not part of the row
M.title = require "modules.title"       -- background layer at the top left

-- Called once by main, after the core's own observers.
function M.init()
    names[M.timeline], names[M.title] = "timeline", "title"
    M.call(M.timeline, "init")
    M.call(M.title, "init")
    for _, name in ipairs({ "pause", "prev", "next", "time", "volume", "fullscreen", "subtitles", "audio", "playlist",
                            "speed", "more" }) do
        names[ROW[name]] = name
        M.call(ROW[name], "init")
    end
end

-- The controls option --------------------------------------------------------

local items = {}       -- the option, resolved: { mod | button | space | gap, cond }
local values = {}      -- last value of each property the conditions name
local handles = {}     -- the watches of those properties
local shown = ""       -- which conditions held at the last check

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

-- A watched property changed: lay out again if the row changed with it.
local function check()
    local now = conditions()
    if now ~= shown then
        shown = now
        ctx.relayout()
    end
end

-- Watch the properties the conditions name now, at most MAX_CONDITIONS
-- (the rest count as false), and stop watching the old ones.
local function watch_conditions(list)
    local keep, seen, ignored = {}, {}, 0
    for _, it in ipairs(list) do
        for _, prop in ipairs(it.props or {}) do
            if not seen[prop] then
                seen[prop] = true
                if #keep < MAX_CONDITIONS then keep[#keep + 1] = prop else ignored = ignored + 1 end
            end
        end
    end
    if ignored > 0 then
        warn(("controls: %d properties in conditions over the first %d are ignored (they count as false)")
            :format(ignored, MAX_CONDITIONS))
    end
    local new, used = {}, {}
    for _, prop in ipairs(keep) do
        used[prop] = true
        -- Watched before the old ones go, so a shared observer stays.
        new[#new + 1] = M.watch(prop, "native", function(v) values[prop] = v; check() end)
    end
    for _, h in ipairs(handles) do M.unwatch(h) end
    handles = new
    for prop in pairs(values) do if not used[prop] then values[prop] = nil end end
end

function M.on_layout(fn) on_layout = fn end

-- Read the controls option again. The caller lays out the row afterwards.
function M.set_controls(s)
    local list, used = {}, {}
    for _, e in ipairs(controls.parse(s, ROW, warn)) do
        local it = { cond = e.cond, props = e.props, space = e.kind == "space", gap = e.kind == "gap" }
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
        elseif e.kind == "button" then
            -- Found when the row is laid out: the script may set it later.
            if used["button:" .. e.name] then
                warn(("controls: 'button:%s' is listed twice, only the first one is shown"):format(e.name))
                it = nil
            else
                used["button:" .. e.name], it.button = true, e.name
            end
        end
        list[#list + 1] = it
    end
    items = list
    watch_conditions(items)
    shown = conditions()
end

-- The elements of the row to lay out now, in order: { mod, width },
-- { gap = true } or { space = true }. Hidden and failed modules, and
-- buttons no script has set yet, are left out.
function M.row()
    local out = {}
    for _, it in ipairs(items) do
        if not it.cond or controls.eval(it.cond, values) then
            local mod = it.mod
            if it.button then
                mod = button.get(it.button)
                if mod then names[mod] = "button:" .. it.button end
            end
            if it.space or it.gap then
                out[#out + 1] = { space = it.space, gap = it.gap }
            elseif mod and M.call(mod, "available") ~= false and M.alive(mod) then
                local w = M.call(mod, "width")
                if w and M.alive(mod) then out[#out + 1] = { mod = mod, width = w } end
            end
        end
    end
    return out
end

return M
