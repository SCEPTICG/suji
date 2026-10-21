-- button:name in the controls option: a button another script defines with
-- the set-button message (core/messages.lua, docs/api.md). One instance per
-- name, a command button (modules/command.lua) made by the first
-- set-button and kept until mpv quits. Until then, or while hidden, it
-- takes no room in the row.

local command = require "modules.command"

local M = {}

M.MAX = 64 -- named buttons; more are refused, so a script cannot fill the memory

local buttons, count = {}, 0

-- The button called name, or nil while no script has set it.
function M.get(name) return buttons[name] end

-- Forget button name (it failed): the next set-button makes a new one.
function M.drop(name)
    if buttons[name] then buttons[name], count = nil, count - 1 end
end

-- Give button name the clean fields f: { icon, command, active, hide,
-- badge, tooltip } (see core/messages.lua). Returns what changed: "layout"
-- (it was shown or hidden), "paint" (it looks different) or nil; or false
-- and the reason when there are M.MAX buttons already.
function M.set(name, f)
    local b = buttons[name]
    if not b then
        if count >= M.MAX then return false, ("more than %d buttons"):format(M.MAX) end
        b = command.new({})
        b.hide = true -- not in the row until now
        buttons[name], count = b, count + 1
    end
    local layout = (b.hide == true) ~= (f.hide == true)
    local paint = b.icon ~= f.icon or b.active ~= f.active or b.badge ~= f.badge
    b.icon, b.command, b.text = f.icon, f.command, f.tooltip
    b.active, b.hide, b.badge = f.active, f.hide, f.badge
    if layout then return "layout" end
    if paint then return "paint" end
end

return M
