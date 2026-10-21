-- Messages from other scripts (core/messages.lua): menus, named buttons,
-- the published menu type, suji-version, hostile JSON and the icons.
local T = require "lib"

local W, H = 1280, 720
local TYPE = "user-data/suji/menu/type"
local CONTROLS = "pause,command:x:script-binding fake/open-menu,button:mine,space,subtitles,more,volume,fullscreen"

local function start(controls)
    T.unload()
    local props = { ["mpv-version"] = "mpv v0.40.0", ["osd-dimensions"] = { w = W, h = H }, duration = 100,
                    pause = true, ["time-pos"] = 50, volume = 100, ["track-list"] = {},
                    ["edition-list"] = { { id = 0 }, { id = 1 } } } -- so more is in the row
    mp = T.fake_mp(props)
    mp.async_observe = true
    mp.script_opts = { controls = controls or CONTROLS }
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = W, h = H })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", true)
    mp.fire("track-list", {})
    mp.mouse(640, 300)
    mp.advance(1)
    return mp
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function cmd(c) return c and table.concat(c, " ") end
local function menu() return package.loaded["core.menu"] end
local function mods() return package.loaded["core.modules"] end
local function layout() return package.loaded["core.layout"] end
local function box_of(name)
    for _, b in ipairs(layout().current().boxes) do
        if mods().name_of(b.mod) == name then return b end
    end
end
local function warnings()
    local n = 0
    for _, l in ipairs(mp.logs) do if l[1] == "warn" or l[1] == "error" then n = n + 1 end end
    return n
end
local function send(name, ...)
    mp.send(name, ...)
    mp.advance(1)
end
local function items(n, prefix)
    local t = {}
    for i = 1, n do t[i] = { title = (prefix or "Item ") .. i, value = { "script-message-to", "fake", "pick", tostring(i) } } end
    return t
end
local function open(def, anchor) send("open-menu", T.json(def), anchor) end
-- The menu's panel, from the black rounded rectangle behind it: x0, x1.
local function panel()
    local a, c = painted():match("\\1c&H000000&\\1a&H66&\\p3}m (%d+) %d+ l (%d+)")
    if not a then return nil end
    return tonumber(a) / 4 - 8, tonumber(c) / 4 + 8
end
local function click(x, y)
    mp.mouse(x, y)
    mp.commands = {}
    mp.button("press")
    local t = {}
    for i, c in ipairs(mp.commands) do t[i] = cmd(c) end
    return table.concat(t, " | ")
end
local function click_box(name)
    local b = assert(box_of(name), name .. " is in the row")
    return click((b.x0 + b.x1) / 2, b.cy)
end
-- Centre of row k of the open menu of n items (no title, all on screen).
local function row_y(k, n) return 646 - n * 30 + (k - 0.5) * 30 end

-- suji-version ---------------------------------------------------------------
start()
local announced = false
for _, c in ipairs(mp.commands) do
    if cmd(c) == "script-message suji-version 0.2.0" then announced = true end
end
T.check(announced, "suji-version sent to every script at start")
T.eq(warnings(), 0, "a start with button:mine and no such button yet: no warning")
T.eq(box_of("button:mine"), nil, "a button no script has set takes no room")

-- open-menu, update-menu, close-menu -----------------------------------------
open({ type = "fake-a", title = "Fake", items = items(3) })
T.check(menu().is_open(), "open-menu opens")
T.eq(menu().open_type(), "fake-a", "of its type")
T.eq(mp.props[TYPE], "fake-a", "the type is published")
T.check(painted():find("}Item 2", 1, true) ~= nil, "its items are drawn")
send("close-menu", "fake-b")
T.check(menu().is_open(), "close-menu of another type leaves it")
send("update-menu", T.json({ type = "fake-b", items = items(3, "Other ") }))
T.check(painted():find("}Item 2", 1, true) and not painted():find("Other", 1, true), "update-menu of another type leaves it")
send("update-menu", T.json({ type = "fake-a", items = items(3, "New ") }))
T.check(painted():find("}New 2", 1, true) ~= nil, "update-menu of its type replaces the items")
T.eq(mp.props[TYPE], "fake-a", "same type after the update")
send("close-menu", "fake-a")
T.check(not menu().is_open(), "close-menu of its type closes")
T.eq(mp.props[TYPE], nil, "the type is deleted on close")
local n_updates = #mp.updates
send("update-menu", T.json({ type = "fake-a", items = items(3) }))
T.check(not menu().is_open(), "update-menu with no menu open opens nothing")
T.eq(#mp.updates, n_updates, "and paints nothing")
open({ type = "fake-a", items = items(3) })
send("close-menu")
T.check(not menu().is_open(), "close-menu with no type closes any menu")
open({ items = items(2) })
T.eq(mp.props[TYPE], "", "a menu with no type publishes \"\"")
send("update-menu", T.json({ items = items(2, "Untyped ") }))
T.check(painted():find("}Untyped 1", 1, true) ~= nil, "and update-menu with no type updates it")
send("close-menu")

-- The update keeps the scroll and does not animate
local long = items(60)
open({ type = "long", items = long })
menu().wheel(-1)
mp.advance(1)
local before = painted():match("}(Item %d+)")
long[1].title = "Changed"
mp.send("update-menu", T.json({ type = "long", items = long }))
T.eq(mp.active_timers() <= 1, true, "an update asks for one paint, no animation")
mp.advance(1)
T.eq(painted():match("}(Item %d+)"), before, "the update keeps the scroll")
-- Opening the same type again replaces it in place
open({ type = "long", items = items(3, "Again ") })
T.check(menu().is_open() and painted():find("}Again 1", 1, true) ~= nil, "open-menu of the open type replaces it")
send("close-menu")
mp.advance(1)
mp.set_opts({ enabled = false })
open({ type = "off", items = items(2) })
T.check(not menu().is_open() and mp.bindings["suji-bar"] == nil, "turned off: open-menu does nothing")
mp.set_opts({ enabled = true })
T.eq(warnings(), 0, "no warnings so far")

-- Choosing: the value goes to mp.commandv, a string to mp.command
open({ type = "pick", items = items(3) })
local x0 = panel()
T.eq(click(x0 + 40, row_y(2, 3)), "script-message-to fake pick 2", "a choice sends the script's own message")
T.check(not menu().is_open(), "and closes the menu")
mp.advance(1)
open({ type = "pick", items = { { title = "S", value = "show-text a; show-text b" } } })
x0 = panel()
mp.mouse(x0 + 40, row_y(1, 1))
mp.button("press")
T.eq(cmd(mp.commands[#mp.commands]), "show-text a; show-text b", "a string value goes whole to mp.command")
mp.advance(1)

-- Own menus publish their type too, and a replace writes it once
click_box("subtitles")
mp.advance(1)
T.eq(mp.props[TYPE], "suji-subtitles", "suji's own menu publishes its type")
mp.writes = {}
open({ type = "fake-a", items = items(2) })
T.eq(#mp.writes, 1, "replacing one menu by another: one write")
T.eq(mp.writes[1] and mp.writes[1][2], "fake-a", "of the new type")
send("update-menu", T.json({ type = "suji-subtitles", items = items(2, "Hijack ") }))
send("close-menu")
click_box("subtitles")
mp.advance(1)
send("update-menu", T.json({ type = "suji-subtitles", items = items(2, "Hijack ") }))
T.check(not painted():find("Hijack", 1, true), "update-menu does not touch suji's own menus")
send("close-menu", "suji-subtitles")
T.check(not menu().is_open(), "but close-menu closes them")
T.eq(mp.props[TYPE], nil, "and the type goes")
mp.advance(1)

-- Anchors ----------------------------------------------------------------------
-- 1. Named in the message or in the JSON
local sub = box_of("subtitles")
open({ type = "a", items = items(2) }, "subtitles")
local p0, p1 = panel()
T.check(p0 <= (sub.x0 + sub.x1) / 2 and p1 >= (sub.x0 + sub.x1) / 2, "the anchor argument: above that button")
send("close-menu")
local cbox = box_of("command:x")
open({ type = "a", anchor = "command:x", items = items(2) })
T.eq(panel(), cbox.x0, "the anchor field: from that button")
send("close-menu")
-- 2. A click on a command: button just before (the script-binding round trip)
mp.advance(5)
T.eq(click_box("command:x"), "script-binding fake/open-menu", "the command button runs its command")
mp.advance(0.2)
open({ type = "hikari", items = items(2) })
T.eq(panel(), cbox.x0, "a menu right after the click comes out of that button")
send("close-menu")
mp.advance(1)
-- 3. Otherwise more
local more = box_of("more")
open({ type = "late", items = items(2) })
p0, p1 = panel()
T.check(p0 <= (more.x0 + more.x1) / 2 and p1 >= (more.x0 + more.x1) / 2, "with no recent click: from more")
send("close-menu")
mp.advance(1)
click_box("command:x")
mp.advance(1.5)
open({ type = "late", items = items(2) }, "nothing-like-this")
p0 = panel()
T.check(p0 ~= cbox.x0, "a click 1.5 s before is too old, an unknown anchor is ignored")
send("close-menu")
mp.advance(1)
-- 4. Without more: the middle
mp.set_opts({ controls = "pause,command:x:script-binding fake/open-menu,space,volume" })
mp.advance(1)
open({ type = "mid", items = items(2) })
p0, p1 = panel()
T.near(p0 + p1, W, "no more in the row: centred", 1)
send("close-menu")
mp.advance(1)
-- The anchor leaves the row: the menu stays and moves to the middle
cbox = box_of("command:x")
open({ type = "follow", items = items(2) }, "command:x")
T.eq(panel(), cbox.x0, "from the command button")
mp.set_opts({ controls = "pause,command:y:show-text moved,command:x:script-binding fake/open-menu,space,volume" })
mp.advance(1)
T.eq(panel(), box_of("command:x").x0, "it follows the button when the row changes")
mp.set_opts({ controls = "pause,space,volume" })
mp.advance(1)
T.check(menu().is_open(), "its button gone, the menu stays open")
p0, p1 = panel()
T.near(p0 + p1, W, "in the middle", 1)
send("close-menu")
mp.advance(1)
T.eq(warnings(), 0, "no warnings in the anchor tests")

-- set-button -----------------------------------------------------------------
start()
local function set(name, def) send("set-button", name, T.json(def)) end
set("mine", { icon = "star", command = { "script-message-to", "fake", "star" } })
local mb = box_of("button:mine")
T.check(mb ~= nil, "set-button: the button named in controls appears")
T.eq(mb.x0, box_of("command:x").x1 + 8, "after the command button")
T.eq(click_box("button:mine"), "script-message-to fake star", "a click runs its command list")
mp.advance(1)
T.eq(mp.props[TYPE], nil, "no menu")
-- a menu right after a click on it comes out of it
open({ type = "from-button", items = items(2) })
T.eq(panel(), mb.x0, "a menu right after the click comes out of the button")
send("close-menu")
mp.advance(1)
-- active, badge, hide
mp.mouse(mb.x0 + 5, mb.cy)
mp.advance(1)
local plain = painted()
set("mine", { icon = "star", active = 1, command = { "script-message-to", "fake", "star" } })
local accent = painted()
T.check(accent ~= plain and #accent > #plain, "active: drawn with a mark")
set("mine", { icon = "star", active = true, badge = "12345", command = { "script-message-to", "fake", "star" } })
T.check(painted():find("}123", 1, true) and not painted():find("1234", 1, true), "the badge, cut to 3 characters")
set("mine", { icon = "star", active = true, badge = "{\\b1}", command = "show-text hi" })
T.check(not painted():find("{\\b1}", 1, true), "a badge cannot inject ASS")
T.eq(click_box("button:mine"), "show-text hi", "a command string goes to mp.command")
mp.advance(1)
local n_upd, n_timers = #mp.updates, mp.active_timers()
mp.send("set-button", "mine", T.json({ icon = "star", active = true, badge = "{\\b1}", command = "show-text hi" }))
T.eq(mp.active_timers(), n_timers, "the same set-button again: no paint asked for")
mp.advance(1)
T.eq(#mp.updates, n_upd, "and none made")
mp.advance(5)
set("mine", { icon = "star", hide = true })
T.eq(box_of("button:mine"), nil, "hide: no room in the row")
set("mine", { icon = "nope" })
T.check(box_of("button:mine") ~= nil, "shown again")
local nb = box_of("button:mine")
T.check(mods().call(nb.mod, "render", nb, 1):find("}N$") ~= nil, "an unknown icon: its initial")
set("mine", {})
T.check(mods().call(nb.mod, "render", nb, 1):find("}M$") ~= nil, "no icon: the initial of the name")
T.eq(warnings(), 0, "no warnings so far")
-- conditions work as for any element
mp.set_opts({ controls = "pause,<user-data/fake/on>button:later,space,volume" })
set("later", { icon = "check" })
T.eq(box_of("button:later"), nil, "its condition does not hold")
mp.fire("user-data/fake/on", true)
T.check(box_of("button:later") ~= nil, "it holds: the button appears")
-- bad names, too many
local w0 = warnings()
send("set-button", "bad name", T.json({ icon = "x" }))
T.eq(warnings(), w0 + 1, "a bad name: one warning")
send("set-button", ("n"):rep(65), T.json({ icon = "x" }))
T.eq(warnings(), w0 + 2, "a long name: one warning")
send("set-button", "ok", "{broken")
T.eq(warnings(), w0 + 3, "broken JSON: one warning")
for i = 3, 64 do mp.send("set-button", "b" .. i, T.json({ icon = "x" })) end
T.eq(warnings(), w0 + 3, "64 buttons in all")
send("set-button", "b65", T.json({ icon = "x" }))
T.eq(warnings(), w0 + 4, "the 65th: one warning")
send("set-button", "b64", T.json({ icon = "check" }))
T.eq(warnings(), w0 + 4, "an existing one can still change")
-- A flood fills neither the log nor the memory
for i = 1, 5000 do mp.send("set-button", "flood" .. i, T.json({ icon = "x" })) end
T.check(warnings() <= w0 + 4 + 21, "a flood: at most 21 lines in the log")
mp.advance(11)
send("set-button", "bad name", "{}")
T.eq(mp.logs[#mp.logs][1], "warn", "warnings come back after a while")

-- Hostile JSON -------------------------------------------------------------------
start()
local function one_warning(name, ...)
    local w = warnings()
    send(name, ...)
    return warnings() - w
end
local function still_works(what)
    open({ type = "check", items = items(2) })
    T.check(menu().open_type() == "check" and painted():find("}Item 2", 1, true) ~= nil, what .. ": suji still works")
    send("close-menu")
    mp.advance(1)
end
T.eq(one_warning("open-menu", '{"type": "x", "items": ['), 1, "broken JSON: one warning")
T.check(not menu().is_open(), "and no menu")
still_works("broken JSON")
T.eq(one_warning("open-menu", '{"type":"x","title":"' .. ("a"):rep(1024 * 1024) .. '"}'), 1, "over 1 MiB: one warning")
still_works("over 1 MiB")
T.eq(one_warning("open-menu", '{"type":"x","items":5}'), 1, "items not a list: one warning")
T.eq(one_warning("open-menu", '[1, 2]'), 0, "a list, not an object: an empty menu with no type")
send("close-menu")
T.eq(one_warning("open-menu", '"text"'), 1, "a string: one warning")
T.eq(one_warning("open-menu"), 1, "nothing: one warning")
T.eq(one_warning("update-menu", "{"), 0, "update-menu with no menu open: not even read")
still_works("bad shapes")
local huge = '{"type":"huge","items":[' .. ("{},"):rep(99999) .. '{}]}'
T.eq(one_warning("open-menu", huge), 1, "100 000 items: one warning")
T.eq(#menu().clean(T.parse_json(huge), false, function() end).items, menu().MAX_ITEMS, "the first 50 000 kept")
still_works("100 000 items")
local weird = { type = "weird", title = { 1 }, selected_index = "x", keep_open = "yes", items = {
    5, "text", true,
    { title = { "t" }, hint = 7, icon = true, value = { 1, 2 }, active = "yes", selectable = "no",
      muted = 1, italic = {}, bold = "x", separator = 2, keep_open = {}, align = { "center" } },
    { title = 12, value = {}, active = -1 },
} }
T.eq(one_warning("open-menu", T.json(weird)), 0, "odd types in every field: no warning, they are left out")
T.check(menu().is_open(), "and the menu opens")
send("close-menu")
T.eq(one_warning("open-menu", T.json({ type = { "x" }, items = items(2) })), 1, "a type that is not a string: one warning")
T.eq(one_warning("open-menu", T.json({ type = ("t"):rep(10240), items = items(2) })), 1, "a type of 10 KB: one warning")
T.check(not menu().is_open(), "and no menu")
still_works("odd types")
-- No action can come in, even if the JSON reader gave a function
local ran = false
mp.parse_json = function() return { type = "evil", items = { { title = "Evil", action = function() ran = true end } } } end
send("open-menu", "{}")
mp.parse_json = nil
T.check(menu().is_open(), "the menu opens")
x0 = panel()
mp.mouse(x0 + 40, row_y(1, 1))
mp.button("press")
mp.advance(1)
T.eq(ran, false, "an action never comes through a message")
-- value empty or huge
mp.commands = {}
open({ type = "values", items = { { title = "Empty", value = "" }, { title = "List", value = {} },
    { title = "Huge", value = ("x"):rep(9000) }, { title = "Long", value = items(65) } } })
x0 = panel()
for k = 1, 4 do
    mp.mouse(x0 + 40, row_y(k, 4))
    mp.button("press")
    mp.advance(1)
    if menu().is_open() then send("close-menu") end
    open({ type = "values", items = { { title = "Empty", value = "" }, { title = "List", value = {} },
        { title = "Huge", value = ("x"):rep(9000) }, { title = "Long", value = items(65) } } })
end
send("close-menu")
local ran_any = false
for _, c in ipairs(mp.commands) do if c[1] ~= "script-message" then ran_any = true end end
T.eq(ran_any, false, "an empty or huge value runs nothing")
local cv = menu().clean_value
T.check(cv("") == nil and cv({}) == nil and cv(("x"):rep(8193)) == nil and cv(items(65)) == nil and cv({ "a", {} }) == nil,
    "values that are empty, too long or not strings are dropped")
T.eq(cmd(cv({ "a", "b" })), "a b", "a list of strings is kept")
-- ASS and control characters
open({ type = "ass", title = "{\\an5}T\1", items = { { title = "{\\b1}Bold\27[31m", hint = "\\N{x}" } } })
local p = painted()
T.check(not p:find("{\\b1}", 1, true) and not p:find("{\\an5}T", 1, true), "ASS in texts is escaped")
T.check(not p:find("[\1\27]"), "control characters do not reach the screen")
T.check(p:find("Bold", 1, true) ~= nil, "the text is still there")
send("close-menu")
still_works("all of it")

-- align and active as a number ---------------------------------------------------
open({ type = "align", items = { { title = "Head", align = "center", selectable = false }, { title = "Right", align = "right" },
    { title = "Left", active = 1 } } })
p = painted()
T.check(p:find("\\an5\\pos%([%d.]+,[%d.]+%)[^\n]*}Head") ~= nil, "align center")
T.check(p:find("\\an6\\pos%([%d.]+,[%d.]+%)[^\n]*}Right") ~= nil, "align right")
T.check(p:find("\\an4\\pos%([%d.]+,[%d.]+%)[^\n]*}Left") ~= nil, "left by default")
T.eq(menu().clean({ items = { { active = 1 }, { active = 0 }, { active = true } } }).items[1].active, true, "active 1")
T.eq(menu().clean({ items = { { active = 0 } } }).items[1].active, false, "active 0")
send("close-menu")

-- user-data/suji/margins ------------------------------------------------------
start()
local MARGINS = "user-data/suji/margins"
T.eq(mp.props[MARGINS] and mp.props[MARGINS].bottom, 62, "the top of the row: 62 px above the bottom edge")
local writes = #mp.writes
mp.fire("pause", false)
mp.mouse(640, 100)
mp.advance(5)
T.eq(mods().ctx.visible(), false, "playing, the mouse away: the controls hide")
T.eq(mp.props[MARGINS].bottom, 62, "the same with the controls hidden")
mp.mouse(640, 690)
mp.advance(0.5)
T.eq(mods().ctx.visible(), true, "shown again")
T.eq(#mp.writes, writes, "showing and hiding the controls writes nothing")
mp.set_opts({ scale = 1.5 })
T.eq(mp.props[MARGINS].bottom, 93, "scale 1.5: 93")
mp.fire("osd-dimensions", { w = 800, h = 600 })
T.eq(mp.props[MARGINS].bottom, 93, "a new window size: the same distance")
writes = #mp.writes
mp.set_opts({ controls = "pause,space,fullscreen" })
T.eq(#mp.writes, writes, "another row of the same height: no write")
mp.set_opts({ controls = "" })
T.eq(mp.props[MARGINS].bottom, 36, "no row: the top of the timeline's zone")
mp.set_opts({ controls = "<user-data/fake/on>pause" })
T.eq(mp.props[MARGINS].bottom, 36, "an element whose condition does not hold: still none")
mp.fire("user-data/fake/on", true)
T.eq(mp.props[MARGINS].bottom, 93, "it appears: the row's top")
mp.set_opts({ enabled = false })
T.eq(mp.props[MARGINS], nil, "enabled=no: deleted")
mp.set_opts({ enabled = true })
T.eq(mp.props[MARGINS] and mp.props[MARGINS].bottom, 93, "back")

-- user-data/suji/menu/type goes with every way a menu closes --------------------
start()
local function opened(t) open({ type = t, items = items(3) }); return mp.props[TYPE] == t end
T.check(opened("esc"), "open")
mp.bindings["suji-menu-esc"].fn()
T.eq(mp.props[TYPE], nil, "Esc")
T.check(opened("outside"), "open")
click(640, 100)
T.eq(mp.props[TYPE], nil, "a click outside")
T.check(opened("choice"), "open")
x0 = panel()
click(x0 + 40, row_y(1, 3))
T.eq(mp.props[TYPE], nil, "a choice")
mp.advance(1)
T.check(opened("first"), "open")
open({ type = "second", items = items(2) })
T.eq(mp.props[TYPE], "second", "another menu on top: its type")
mp.emit("end-file")
T.eq(mp.props[TYPE], nil, "a new file closes a menu from a message")
T.check(opened("closed"), "open")
send("close-menu")
T.eq(mp.props[TYPE], nil, "close-menu")
T.check(opened("off"), "open")
mp.set_opts({ enabled = false })
T.eq(mp.props[TYPE], nil, "enabled=no")
mp.set_opts({ enabled = true })
mp.advance(1)
click_box("subtitles")
mp.advance(1)
mp.emit("end-file")
T.eq(mp.props[TYPE], "suji-subtitles", "suji's own menu stays open across files (it follows the new one)")
package.loaded["modules.subtitles"].render = function() error("broken") end
mp.advance(1)
T.eq(mp.props[TYPE], nil, "its module failed")

-- Choosing: the value runs before the menu closes ---------------------------------
start()
local seen
local commandv = mp.commandv
mp.commandv = function(...) seen = mp.props[TYPE]; return commandv(...) end
open({ type = "order", items = items(2) })
x0 = panel()
click(x0 + 40, row_y(1, 2))
T.eq(seen, "order", "the value runs while the type is still published")
T.eq(mp.props[TYPE], nil, "then it goes")
mp.commandv = commandv
mp.advance(1)
-- An item that opens another menu right away: that one stays
local ctx_more = mods().ctx_of(package.loaded["modules.more"])
local ctx_subs = mods().ctx_of(package.loaded["modules.subtitles"])
ctx_more.open_menu({ type = "first", items = { { title = "Next", action = function()
    ctx_subs.open_menu({ type = "next", items = items(2) }, box_of("subtitles"))
end } } }, box_of("more"))
mp.advance(1)
x0 = panel()
click(x0 + 40, row_y(1, 1))
T.eq(menu().open_type(), "next", "the menu the item opened stays open")
T.eq(mp.props[TYPE], "next", "with its type")
menu().close()
mp.advance(1)

-- selected_index and items that cannot be chosen -----------------------------------
local function key(k) mp.bindings["suji-menu-" .. k].fn(); mp.advance(0.1) end
local CHOICES = { { title = "Head", selectable = false, muted = true },
                  { title = "A", value = { "show-text", "A" } },
                  { title = "Disabled", hint = "not now", selectable = false, value = { "show-text", "D" } },
                  { title = "C", value = { "show-text", "C" } } }
local function enter()
    mp.commands = {}
    key("enter")
    return cmd(mp.commands[#mp.commands])
end
open({ type = "sel", selected_index = 4, items = CHOICES })
T.eq(enter(), "show-text C", "selected_index counts from 1, headers too: 4 is C")
open({ type = "sel", selected_index = 2, items = CHOICES })
T.eq(enter(), "show-text A", "2 is A")
open({ type = "sel", selected_index = 2, items = CHOICES })
key("down") -- the first key shows the cursor on the selected item
key("down")
T.eq(enter(), "show-text C", "the keys skip the item that cannot be chosen")
open({ type = "sel", selected_index = 4, items = CHOICES })
key("up")
key("up")
T.eq(enter(), "show-text A", "both ways")
open({ type = "sel", items = CHOICES })
T.check(painted():find("\\1a&H80&[^}]*}Disabled") ~= nil, "it is drawn dimmed")
x0 = panel()
T.eq(click(x0 + 40, row_y(3, 4)), "", "a click on it does nothing")
T.check(menu().is_open(), "and the menu stays")
send("close-menu")

-- keep_open and update-menu: the cursor stays on the same line ----------------------
open({ type = "lang", title = "Language", keep_open = true, items = items(5) })
key("down")
key("down")
send("update-menu", T.json({ type = "lang", title = "Idioma", keep_open = true, items = items(5, "Elemento ") }))
mp.commands = {}
key("enter")
T.eq(cmd(mp.commands[#mp.commands]), "script-message-to fake pick 2", "the keys' line, after new texts and title")
x0 = panel()
mp.mouse(x0 + 40, row_y(4, 5))
mp.advance(0.1)
send("update-menu", T.json({ type = "lang", title = "Sprache", keep_open = true, items = items(5, "Eintrag ") }))
T.check(painted():find("}Eintrag 4", 1, true) ~= nil, "the new texts")
mp.commands = {}
key("enter")
T.eq(cmd(mp.commands[#mp.commands]), "script-message-to fake pick 4", "the line under the mouse, too")
T.check(menu().is_open(), "keep_open: still open")
send("close-menu")

-- Icons ------------------------------------------------------------------------
local icons = require "core.icons"
local names = icons.names()
T.check(#names >= 27, "the icons with names: " .. #names)
for _, name in ipairs({ "text_fields", "auto_awesome", "speed", "history", "palette", "system_update_alt", "star",
                        "language", "settings", "info", "screenshot", "next", "prev", "close", "check" }) do
    local shape, width = icons.shape(name, 50, 50, 22)
    local ok = shape ~= nil and #shape > 0 and width > 0
    for _, line in ipairs(shape or {}) do
        ok = ok and #line >= 4 and #line % 2 == 0
        for _, n in ipairs(line) do ok = ok and n == n and n >= 38 and n <= 62 end
    end
    T.check(ok, name .. ": lines inside its square")
end
T.eq(icons.shape("no-such-icon", 0, 0, 22), nil, "an unknown name: no lines")

T.done("test_messages")
