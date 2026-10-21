-- Action buttons (modules/actions.lua) through show-action and hide-action:
-- where they go, the limits, hostile input, menus, a new file, enabled=no,
-- clicks and repaints.
local T = require "lib"

local W, H = 1280, 720
-- The row's top is at 658 (margins.bottom 62): buttons from 610 to 646.
local CY, RIGHT = 628, 1260

local function start()
    T.unload()
    mp = T.fake_mp({ ["mpv-version"] = "mpv v0.40.0", ["osd-dimensions"] = { w = W, h = H }, duration = 100,
                     pause = false, ["time-pos"] = 50 })
    mp.script_opts = { controls = "pause,time,space,volume,fullscreen" }
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = W, h = H })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.mouse(640, 100)
    mp.advance(5) -- the mouse is still: the controls hide
    return mp
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function has(t) return painted():find("}" .. t, 1, true) ~= nil end
local function warnings()
    local n = 0
    for _, l in ipairs(mp.logs) do if l[1] == "warn" or l[1] == "error" then n = n + 1 end end
    return n
end
local function send(name, ...)
    mp.send(name, ...)
    mp.advance(1)
end
local function show(id, text, command)
    send("show-action", id, T.json({ text = text, command = command or { "script-message-to", "fake", id } }))
end
local function click(x, y)
    mp.mouse(x, y)
    mp.commands = {}
    mp.button("press")
    local t = {}
    for i, c in ipairs(mp.commands) do t[i] = table.concat(c, " ") end
    return table.concat(t, " | ")
end
local function visible() return package.loaded["core.modules"].ctx.visible() end
local function menu() return package.loaded["core.menu"] end

-- Showing, with the controls hidden -----------------------------------------
start()
T.check(not visible(), "the controls are hidden")
T.eq(mp.active_timers(), 0, "no timers at rest")
show("skip-op", "Skip opening ›")
T.check(has("Skip opening ›"), "show-action draws the button")
T.check(not visible(), "with the controls still hidden")
T.check(painted():find("\\1c&H000000&\\1a&H66&", 1, true) ~= nil, "on a black panel at 60%")
T.eq(mp.active_timers(), 0, "no timers once it has faded in")
T.eq(mp.bindings["suji-bar"], nil, "no bindings with the cursor elsewhere")
local n = #mp.updates
send("show-action", "skip-op", T.json({ text = "Skip opening ›", command = { "script-message-to", "fake", "skip-op" } }))
T.eq(#mp.updates, n, "the same show-action again does not repaint")
T.eq(mp.active_timers(), 0, "nor asks for a paint")
show("skip-op", "Skip ending ›")
T.check(has("Skip ending ›") and not has("Skip opening"), "show-action of the same id changes it")
show("skip-op", "Skip ending ›", "seek 90")
T.eq(click(RIGHT - 10, CY), "seek 90", "a new command alone counts as a change")
mp.mouse(640, 100)
mp.advance(5)
T.eq(warnings(), 0, "no warnings so far")

-- Fading out ----------------------------------------------------------------------
mp.send("hide-action", "skip-op")
mp.advance(0.05)
T.check(has("Skip ending ›"), "a hidden button fades out")
T.check(mp.active_timers() > 0, "painting while it fades")
mp.advance(1)
T.check(not has("Skip"), "and is gone")
T.eq(mp.active_timers(), 0, "no timers after the fade")
send("hide-action", "nothing-here")
T.eq(warnings(), 0, "hide-action of an unknown id says nothing")

-- Clicks -----------------------------------------------------------------------------
start()
show("next", "Next episode ›")
mp.mouse(RIGHT - 10, CY)
mp.advance(0.1)
T.check(mp.bindings["suji-bar"] ~= nil, "on the button: the mouse is bound")
T.check(painted():find("\\1c&HFFFFFF&\\1a&HE6&", 1, true) ~= nil, "and it is lit")
mp.commands = {}
mp.button("press")
T.eq(table.concat(mp.commands[1] or {}, " "), "script-message-to fake next", "a click runs its command")
T.check(has("Next episode ›"), "and the button stays")
mp.send("hide-action", "next")
mp.advance(0.1)
T.check(mp.bindings["suji-bar"] ~= nil, "hidden right after the click: the bindings wait for a double click")
mp.advance(1)
T.eq(mp.bindings["suji-bar"], nil, "then they go")
show("next", "Next episode ›", "playlist-next")
T.eq(click(RIGHT - 10, CY), "playlist-next", "a string runs with mp.command")
T.eq(click(RIGHT - 10, CY - 30), "", "a click above it is not its")
T.eq(click(RIGHT + 10, CY), "", "nor one right of it")
mp.advance(1)
mp.mouse(RIGHT - 10, CY)
mp.commands = {}
mp.button("press")
mp.button("press")
T.eq(#mp.commands, 1, "a double click on a button that stays runs it once")
T.check(mp.bindings["suji-bar"] ~= nil, "and suji keeps the second click")
mp.advance(1)
mp.commands = {}
mp.button("press")
T.eq(#mp.commands, 1, "after the double-click time, a click runs it again")
mp.mouse(640, 100)
mp.advance(5)
T.eq(mp.bindings["suji-bar"], nil, "away from it: no bindings")
T.eq(mp.props["input-builtin-dragging"], true, "and window dragging is back")
send("show-action", "none", T.json({ text = "No command" }))
T.eq(warnings(), 0, "a button with no command is fine")
T.check(has("No command"), "and drawn")
send("hide-action")
T.eq(click(RIGHT - 10, CY), "", "a hidden button takes no clicks")

-- Several at once ---------------------------------------------------------------
start()
for i = 1, 5 do show("a" .. i, "Action " .. i) end
local shown = 0
for i = 1, 5 do if has("Action " .. i .. "") then shown = shown + 1 end end
T.eq(shown, 4, "at most 4 on screen")
T.check(not has("Action 5"), "the fifth waits")
-- Right to left: the first one is at the right edge.
local x1 = painted():match("%\\pos%((%d+)[%.%d]*,628%.0%)[^\n]*}Action 1")
local x2 = painted():match("%\\pos%((%d+)[%.%d]*,628%.0%)[^\n]*}Action 2")
T.check(x1 and x2 and tonumber(x1) > tonumber(x2), "the first is right of the second")
T.check(x1 and tonumber(x1) < RIGHT, "inside the right margin")
-- A narrow window: those that would leave it on the left wait too.
mp.fire("osd-dimensions", { w = 300, h = H })
mp.advance(1)
shown = 0
for i = 1, 5 do if has("Action " .. i) then shown = shown + 1 end end
T.eq(shown, 2, "300 px wide: two fit")
mp.fire("osd-dimensions", { w = W, h = H })
mp.advance(1)
send("hide-action", "a2")
mp.advance(1)
T.check(has("Action 5") and not has("Action 2"), "hiding one makes room for the fifth")
send("hide-action")
mp.advance(1)
T.check(not has("Action"), "hide-action with no id hides them all")
T.eq(mp.active_timers(), 0, "no timers left")

-- At most 16 ids
for i = 1, 16 do show("id" .. i, "Id " .. i) end
local w = warnings()
show("id17", "Id 17")
T.eq(warnings(), w + 1, "a 17th id is refused with a warning")
show("id3", "Id three")
T.eq(warnings(), w + 1, "changing one of the 16 is fine")
for i = 1, 16 do send("hide-action", "id" .. i) end
mp.advance(1)
T.check(not has("Id 17"), "the 17th was not kept")
show("id17", "Id 17")
T.check(has("Id 17"), "with room again, it is kept")
send("hide-action")

-- Hiding and showing in a loop does not pile up fading buttons: one per
-- place, at most 4, and a show of the same id takes its fade back.
local function loop(n, id)
    local most, longest = 0, 0
    for i = 1, n do
        mp.send("hide-action")
        for k = 1, 4 do mp.send("show-action", id(i, k), T.json({ text = "Ghost", command = "quit" })) end
        mp.advance(0.0001)
        local d = painted()
        most, longest = math.max(most, select(2, d:gsub("}Ghost", ""))), math.max(longest, #d)
    end
    return most, longest
end
local most, longest = loop(1000, function(i, k) return "g" .. (i * 4 + k) % 16 end)
T.check(most <= 8, ("new ids in a loop: at most 8 buttons in a frame (%d)"):format(most))
T.check(longest <= 8 * 600, ("and a frame of bounded size (%d bytes)"):format(longest))
send("hide-action")
most, longest = loop(1000, function(_, k) return "g" .. k end)
T.check(most <= 4, ("the same ids in a loop: at most 4 buttons in a frame (%d)"):format(most))
send("hide-action")
mp.advance(1)
T.check(not has("Ghost"), "all gone after the loops")
T.eq(mp.active_timers(), 0, "no timers after the loops")

-- Hostile input -------------------------------------------------------------------
start()
local function refused(name, ...)
    local before = warnings()
    send(name, ...)
    return warnings() == before + 1 and not painted():find("\\1a&H66&", 1, true)
end
T.check(refused("show-action", "x", "{"), "broken JSON: a warning, no button")
T.check(refused("show-action", "x", "[1]"), "a list")
T.check(refused("show-action", "x", '"text"'), "a string")
T.check(refused("show-action", "x", ""), "no JSON")
T.check(refused("show-action", "x", nil), "nothing at all")
T.check(refused("show-action", "x", '{"text":"' .. ("a"):rep(1024 * 1024) .. '"}'), "JSON over 1 MiB")
T.check(refused("show-action", "x", T.json({ command = "quit" })), "no text")
T.check(refused("show-action", "x", T.json({ text = "" })), "an empty text")
T.check(refused("show-action", "x", '{"text":5}'), "a text that is not a string")
T.check(refused("show-action", "bad id", T.json({ text = "A" })), "an id with a space")
T.check(refused("show-action", ("i"):rep(65), T.json({ text = "A" })), "an id over 64")
T.check(refused("show-action", nil, nil), "no id")
local before = warnings()
send("show-action", "cmd", T.json({ text = "Bad command", command = { "seek", 5 } }))
T.eq(warnings(), before + 1, "a bad command: a warning")
T.check(has("Bad command"), "and the button without it")
T.eq(click(RIGHT - 10, CY), "", "which runs nothing")
send("hide-action")
mp.mouse(640, 100)
send("show-action", "long", T.json({ text = ("x"):rep(100) }))
T.check(has(("x"):rep(64) .. "{") or has(("x"):rep(64) .. "\n") or painted():find("}" .. ("x"):rep(64) .. "$"),
    "a long text is cut to 64 bytes")
T.check(not has(("x"):rep(65)), "not more")
send("show-action", "long", T.json({ text = ("é"):rep(40) }))
T.check(painted():find("}" .. ("é"):rep(32) .. "$") ~= nil or painted():find("}" .. ("é"):rep(32) .. "\n", 1, true) ~= nil,
    "cut between characters")
send("show-action", "long", T.json({ text = "One\ntwo\1{\\b1}" }))
T.check(has("One?two?\\{\\\226\128\139b1\\}"), "control characters become ?, braces stay text")
send("hide-action")

-- A menu covers them --------------------------------------------------------------
start()
show("skip", "Skip ›")
send("open-menu", T.json({ type = "m", items = { { title = "Item", value = { "x" } } } }))
T.check(menu().is_open(), "a menu opens")
T.check(not has("Skip ›"), "the button goes while it is open")
mp.mouse(RIGHT - 10, CY)
mp.advance(0.1)
mp.commands = {}
mp.button("press")
T.check(not menu().is_open(), "a click where it was only closes the menu")
T.eq(#mp.commands, 0, "and runs nothing")
mp.advance(1)
T.check(has("Skip ›"), "the button is back once the menu is closed")
mp.mouse(640, 100)
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers")

-- A new file -------------------------------------------------------------------------
show("skip2", "Skip 2 ›")
mp.emit("end-file")
mp.advance(1)
T.check(not has("Skip"), "a new file removes them all")
show("skip", "Skip ›")
T.check(has("Skip ›"), "a new show-action works")

-- enabled=no --------------------------------------------------------------------------
mp.set_opts({ enabled = false })
mp.advance(1)
T.check(not has("Skip"), "turned off: none on screen")
T.eq(mp.bindings["suji-bar"], nil, "and no bindings")
show("off", "Off ›")
mp.set_opts({ enabled = true })
mp.advance(1)
T.check(not has("Skip") and not has("Off"), "turned on again: the old ones are gone and none came while off")
show("on", "On ›")
T.check(has("On ›"), "a show-action after turning on works")
T.eq(mp.active_timers(), 0, "no timers at rest")
T.eq(warnings(), 0, "no warnings")

T.done("test_actions")
