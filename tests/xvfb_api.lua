-- Real test of the messages, loaded before suji in a virtual X display (see
-- tests/run.sh). It behaves like a script of hikari: it puts a command:
-- button in suji's controls that runs its own script-binding, answers that
-- binding with open-menu, gets the choice back as a message to itself and
-- watches user-data/suji/menu/type. Then it sets a button of its own with
-- set-button and clicks it.
--
-- Window: 640x480. The row is centred on y 440: pause (20-64), the command
-- button (72-116), button:fake (124-168). A menu of three items from the
-- command button has x 72 onwards and rows at y 316, 346 and 376 (30 px
-- each, ending 12 px above the row's zones); from anywhere else (more is
-- not in the row: the middle) it would not reach x 100.

local msg = require "mp.msg"
local utils = require "mp.utils"

local NAME = mp.get_script_name()
local started, done = false, false
local version, picked, clicked
local types = {} -- every value of user-data/suji/menu/type, in order

local function finish(ok, text)
    if done then return end
    done = true
    if ok then msg.info("xvfb-api: ok " .. text) else msg.error("xvfb-api: FAIL " .. text) end
    mp.commandv("quit", ok and "0" or "1")
end

mp.register_script_message("suji-version", function(v) version = v end)
mp.register_script_message("picked", function(i) picked = i end)
mp.register_script_message("button-clicked", function() clicked = true end)
mp.observe_property("user-data/suji/menu/type", "native", function(_, v) types[#types + 1] = tostring(v) end)

-- What hikari does when its button is clicked.
mp.add_key_binding(nil, "open-menu", function()
    local items = {}
    for i = 1, 3 do
        items[i] = { title = "Entry " .. i, value = { "script-message-to", NAME, "picked", tostring(i) } }
    end
    mp.commandv("script-message-to", "suji", "open-menu", utils.format_json({ type = "xvfb-api", items = items }))
end)

mp.commandv("change-list", "script-opts", "append",
    "suji-controls=pause,command:star:script-binding " .. NAME .. "/open-menu,button:fake,space,volume,fullscreen")

local steps = {}
local function after(dt, fn) steps[#steps + 1] = { dt, fn } end

local function run(i)
    local s = steps[i]
    if not s or done then return end
    mp.add_timeout(s[1], function()
        if done then return end
        s[2]()
        run(i + 1)
    end)
end

local function click_at(x, y)
    after(0.3, function() mp.commandv("mouse", tostring(x), tostring(y)) end)
    after(0.3, function() mp.commandv("keypress", "MBTN_LEFT") end)
end

click_at(94, 440) -- the command button: hikari opens its menu
after(0.3, function()
    if types[#types] ~= "xvfb-api" then finish(false, "the menu type is not published: " .. table.concat(types, ",")) end
end)
click_at(100, 361) -- second row, only there if the menu came out of the button
after(0.4, function()
    if picked ~= "2" then finish(false, "the choice did not come back (" .. tostring(picked) .. ")") end
    if types[#types] ~= "nil" then finish(false, "the menu type was not deleted: " .. table.concat(types, ",")) end
    local ok = mp.commandv("script-message-to", "suji", "set-button", "fake",
        utils.format_json({ icon = "check", command = { "script-message-to", NAME, "button-clicked" } }))
    if not ok then finish(false, "script-message-to suji failed") end
end)
click_at(146, 440) -- button:fake, there now
after(0.4, function()
    if not clicked then finish(false, "the click on button:fake did not arrive") end
    local missing = mp.commandv("script-message-to", "no-such-script", "hello")
    finish(version == "0.2.0" and missing == nil,
        ("suji-version %s, picked %s, types %s, button clicked, a message to no script gives %s"):format(
            tostring(version), picked, table.concat(types, ","), tostring(missing)))
end)

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    run(1)
end)

mp.add_timeout(30, function() finish(false, "timed out") end)
