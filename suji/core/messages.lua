-- Messages from other scripts: open-menu, update-menu, close-menu,
-- set-button, show-action and hide-action (docs/api.md has them all). The
-- work is done by the menu service (core/menu.lua), the named buttons
-- (modules/button.lua) and the action buttons (modules/actions.lua); this
-- file reads the arguments.
--
-- Any script, and any client of mpv's IPC, can send these messages, so
-- every argument is untrusted: JSON is size-checked before it is parsed,
-- menus are cleaned untrusted (never an action), names and texts are cut,
-- and all warnings share one limit, so a flood fills neither the memory
-- nor the log. A handler that fails is logged, never stops suji.

local msg = require "mp.msg"
local utils = require "mp.utils"
local opts = require "core.options"
local draw = require "core.draw"
local text = require "core.text"
local painter = require "core.painter"
local layout = require "core.layout"
local modules = require "core.modules"
local menu = require "core.menu"
local controls = require "core.controls"
local command = require "modules.command"
local button = require "modules.button"
local actions = require "modules.actions"

local M = {}

M.MAX_JSON = 1024 * 1024 -- bytes
-- A menu that comes this soon after a click on a command: or button:
-- button opens from that button: the click usually asked for it (through
-- script-binding), and a script answers in milliseconds; a second leaves
-- room for a slow one, and a menu opened later by a key does not jump to a
-- button clicked long before.
M.RECENT = 1 -- s
local MAX_ICON, MAX_BADGE, MAX_TOOLTIP = 32, 3, 200
local MAX_WARNINGS, WARN_SPAN = 20, 10 -- at most this many in so many seconds

local warn_since, warnings = -math.huge, 0
local function warn(line)
    local now = mp.get_time()
    if now - warn_since > WARN_SPAN then warn_since, warnings = now, 0 end
    warnings = warnings + 1
    if warnings <= MAX_WARNINGS then
        msg.warn(line)
    elseif warnings == MAX_WARNINGS + 1 then
        msg.warn("too many warnings about messages, the next ones are left out for a while")
    end
end

-- The JSON object in s, or nil after a warning. mpv marks what
-- parse_json makes: an object has the metatable mp.MAP, a list mp.ARRAY
-- (both are plain tables in Lua, and an empty one looks the same).
local function decode(what, s)
    if type(s) ~= "string" or s == "" then return warn(what .. ": no JSON") end
    if #s > M.MAX_JSON then return warn(("%s: JSON over %d bytes, ignored"):format(what, M.MAX_JSON)) end
    local ok, t = pcall(utils.parse_json, s)
    -- mp.MAP is not documented: an mpv without it gets any table, as before.
    if not ok or type(t) ~= "table" or (mp.MAP and getmetatable(t) ~= mp.MAP) then
        return warn(what .. ": not a JSON object, ignored")
    end
    return t
end

-- Where a menu from a message comes out: the element of the row called
-- name, else the button clicked just before, else more; nil: the middle.
local function anchor(name)
    local placed = layout.current()
    local pressed, at = command.last_press()
    return type(name) == "string" and layout.named(placed, name)
        or pressed and mp.get_time() - at <= M.RECENT and layout.find(placed, pressed)
        or layout.named(placed, "more")
end

-- The fields of set-button that suji keeps, checked and cut.
local function clean_button(name, def)
    local f = { hide = def.hide == true,
                active = def.active == true or (type(def.active) == "number" and def.active ~= 0) }
    local icon = def.icon
    -- An unknown icon draws its initial; with none, the name's.
    f.icon = type(icon) == "string" and #icon <= MAX_ICON and icon:match("^[%w_%-]+$") and icon or name
    local badge = def.badge
    if type(badge) == "number" then badge = tostring(badge) end
    if type(badge) == "string" and badge ~= "" then
        f.badge = draw.printable(text.prefix(badge:sub(1, 4 * MAX_BADGE), MAX_BADGE))
    end
    if type(def.tooltip) == "string" then
        f.tooltip = draw.printable(text.prefix(def.tooltip:sub(1, 4 * MAX_TOOLTIP), MAX_TOOLTIP))
    end
    f.command = menu.clean_value(def.command)
    if def.command ~= nil and not f.command then
        warn(("set-button %s: the command is not a string or a list of strings, or is too long"):format(name))
    end
    return f
end

-- A name of set-button or an id of show-action: letters, digits, _ and -.
local function good_name(name)
    return type(name) == "string" and #name <= controls.MAX_NAME and name:match("^[%w_%-]+$") ~= nil
end

-- The text of show-action: one line of at most actions.MAX_TEXT bytes,
-- cut between characters, printable; nil when there is none.
local function action_text(t)
    if type(t) ~= "string" or t == "" then return nil end
    if #t > actions.MAX_TEXT then
        t = t:sub(1, actions.MAX_TEXT)
        -- The last character, when it was cut, goes whole.
        local i = t:find("[\192-\255][\128-\191]*$")
        local b = i and t:byte(i)
        if b and #t - i + 1 < (b >= 240 and 4 or b >= 224 and 3 or 2) then t = t:sub(1, i - 1) end
    end
    return t ~= "" and draw.printable(t) or nil
end

local function on(name, fn)
    mp.register_script_message(name, function(...)
        local ok, err = pcall(fn, ...)
        if not ok then warn(("%s failed: %s"):format(name, draw.printable(err, 300))) end
    end)
end

-- open-menu <json> [anchor]; nothing while suji is turned off.
on("open-menu", function(json, name)
    if not opts.enabled then return end
    local def = decode("open-menu", json)
    if not def then return end
    if name == nil or name == "" then name = def.anchor end
    menu.open_message(def, anchor(name), warn)
end)

-- update-menu <json>: only the open menu of the same type, if a message
-- opened it; it never opens one.
on("update-menu", function(json)
    if not menu.message_open() then return end -- not read for nothing
    local def = decode("update-menu", json)
    if def then menu.update_message(def, warn) end
end)

-- close-menu [type]
on("close-menu", function(mtype)
    local open = menu.open_type()
    if open and (mtype == nil or mtype == "" or mtype == open) then menu.close() end
end)

-- set-button <name> <json>
on("set-button", function(name, json)
    if not good_name(name) then
        return warn(("set-button: bad name '%s' (letters, digits, _ and -, at most %d)"):format(
            draw.printable(name, 64), controls.MAX_NAME))
    end
    local def = decode("set-button " .. name, json)
    if not def then return end
    -- A button that failed stays off for good: a set-button makes it anew.
    local old = button.get(name)
    if old and not modules.alive(old) then button.drop(name) end
    local changed, why = button.set(name, clean_button(name, def))
    if changed == false then
        warn(("set-button %s: %s, ignored"):format(name, why))
    elseif changed == "layout" then
        modules.ctx.relayout()
    elseif changed == "paint" and modules.ctx.visible() then
        painter.request()
    end
end)

-- show-action <id> <json>; nothing while suji is turned off.
on("show-action", function(id, json)
    if not opts.enabled then return end
    if not good_name(id) then
        return warn(("show-action: bad id '%s' (letters, digits, _ and -, at most %d)"):format(
            draw.printable(id, 64), controls.MAX_NAME))
    end
    local def = decode("show-action " .. id, json)
    if not def then return end
    local t = action_text(def.text)
    if not t then return warn(("show-action %s: no text, ignored"):format(id)) end
    local c = menu.clean_value(def.command)
    if def.command ~= nil and not c then
        warn(("show-action %s: the command is not a string or a list of strings, or is too long"):format(id))
    end
    local ok, why = actions.set(id, { text = t, command = c })
    if ok == false then warn(("show-action %s: %s, ignored"):format(id, why)) end
end)

-- hide-action [id]: with no id, all of them.
on("hide-action", function(id)
    if id == nil or id == "" then actions.hide() elseif type(id) == "string" then actions.hide(id) end
end)

return M
