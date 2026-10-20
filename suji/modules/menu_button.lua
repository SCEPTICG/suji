-- A button of the row that opens a menu: what subtitles, audio, playlist
-- and more have in common, and the helpers they share. See core/menu.lua
-- for the menu and core/modules.lua for the module contract.
--
-- spec: { icon, build, live, init?, available? }
--   build(ctx)  the menu, read from mpv's properties when it opens
--   live        properties watched only while the menu is open: when one
--               changes (another script picks a track, a new file starts)
--               the menu is built again and replaces the one on screen
-- init and available are the module's own (see the contract).

local msg = require "mp.msg"

local unpack = table.unpack or unpack

local M = {}

M.MAX_ITEMS = 50000 -- items a menu can list (the menu service keeps as many)
local MAX_TRACKS = 500
local MAX_CLIPBOARD = 4096 -- bytes of the clipboard read

function M.new(spec)
    local b = { init = spec.init, available = spec.available }
    local handles -- watches of spec.live while the menu is open

    function b.width(ctx) return ctx.BUTTON * ctx.state.scale end

    function b.render(ctx, box, v)
        return ctx.icon(spec.icon, (box.x0 + box.x1) / 2, box.cy, v)
    end

    function b.menu_closed(ctx)
        for _, h in ipairs(handles or {}) do ctx.unwatch(h) end
        handles = nil
    end

    function b.press(ctx, box)
        if not ctx.open_menu(spec.build(ctx), box) then return end
        b.menu_closed(ctx)
        handles = {}
        local ready = false -- a value already seen is delivered at once: not new
        for _, prop in ipairs(spec.live) do
            handles[#handles + 1] = ctx.watch(prop, "native", function()
                if ready then ctx.update_menu(spec.build(ctx)) end
            end)
        end
        ready = true
    end

    return b
end

-- A group header: an item with no value that cannot be chosen.
function M.header(title, hint)
    return { title = title, hint = hint, selectable = false, muted = true, italic = true }
end

-- The tracks of one type ("sub", "audio", "video") in track-list, as
-- items that write the id to prop (sid, aid, vid). Title: title, else the
-- language, else "Track N"; hint: the language and the flags.
function M.track_items(list, kind, prop)
    local out = {}
    for _, t in ipairs(type(list) == "table" and list or {}) do
        if #out >= MAX_TRACKS then break end
        local id = type(t) == "table" and t.type == kind and tonumber(t.id)
        if id then
            local title = type(t.title) == "string" and t.title ~= "" and t.title or nil
            local lang = type(t.lang) == "string" and t.lang ~= "" and t.lang or nil
            local hint = {}
            if title and lang then hint[1] = lang end
            for _, flag in ipairs({ "forced", "default", "external" }) do
                if t[flag] == true then hint[#hint + 1] = flag end
            end
            out[#out + 1] = { title = title or lang or ("Track %d"):format(id),
                              hint = #hint > 0 and table.concat(hint, ", ") or nil,
                              value = { "set", prop, ("%d"):format(id) }, active = t.selected == true }
        end
    end
    return out
end

-- How many tracks of type kind track-list has.
function M.count(list, kind)
    local n = 0
    for _, t in ipairs(type(list) == "table" and list or {}) do
        if type(t) == "table" and t.type == kind then n = n + 1 end
    end
    return n
end

-- mpv 0.40 added the clipboard property; older versions have none.
local clipboard
function M.has_clipboard()
    if clipboard == nil then
        clipboard = false
        local list = mp.get_property_native("property-list")
        for _, p in ipairs(type(list) == "table" and list or {}) do
            if p == "clipboard" then clipboard = true; break end
        end
    end
    return clipboard
end

-- First line of s without the spaces around it; linear in the length.
local function first_line(s)
    s = s:sub(1, MAX_CLIPBOARD):match("^[^\r\n]*")
    local i = s:find("%S")
    return i and s:match("^.*%S", i) or ""
end

-- An item that runs command with the first line of the clipboard, read
-- when it is chosen. The text is one argument of mp.commandv: it is never
-- parsed as commands, and ${...} in it is not expanded.
function M.clipboard_item(title, command, ...)
    local extra = { ... }
    return { title = title, action = function()
        local s = mp.get_property_native("clipboard/text")
        local line = type(s) == "string" and first_line(s) or ""
        if line == "" then
            mp.commandv("show-text", "Clipboard is empty", "1500")
            return
        end
        local ok, err = mp.commandv(command, line, unpack(extra))
        if ok == nil and err then msg.warn(("%s from the clipboard failed: %s"):format(command, tostring(err))) end
    end }
end

return M
