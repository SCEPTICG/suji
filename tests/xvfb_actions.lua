-- Loaded after suji by tests/xvfb_actions.sh, which clicks with real X
-- events. It behaves like hikari during an opening: it shows an action
-- button whose command is a message to itself, and hides it when that
-- message comes. Then it shows a button it never hides, for a double
-- click that must run its command once. It logs each step; run.sh reads
-- the log.
local msg = require "mp.msg"
local utils = require "mp.utils"

local NAME = mp.get_script_name()
local started, clicks, stays = false, 0, 0

mp.register_script_message("skip", function()
    clicks = clicks + 1
    msg.info("clicked " .. clicks)
    mp.commandv("script-message-to", "suji", "hide-action", "skip-op")
    -- After the shell script's second click, which must find nothing.
    mp.add_timeout(2, function()
        local ok = mp.commandv("script-message-to", "suji", "show-action", "stay",
            utils.format_json({ text = "Stay ›", command = { "script-message-to", NAME, "stay" } }))
        msg.info("stay shown " .. tostring(ok))
    end)
end)

mp.register_script_message("stay", function()
    stays = stays + 1
    msg.info("stayed " .. stays)
end)

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    mp.add_timeout(0.5, function()
        local ok = mp.commandv("script-message-to", "suji", "show-action", "skip-op",
            utils.format_json({ text = "Skip opening ›", command = { "script-message-to", NAME, "skip" } }))
        msg.info("shown " .. tostring(ok))
    end)
end)

mp.add_timeout(20, function() mp.commandv("quit") end)
