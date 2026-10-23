-- Loaded next to suji in the smoke test: sends a two-line title with the
-- episode's name (the optional third part of set-title), checks
-- that mpv's OSC is off, then changes suji's options at run time (a new
-- scale, then enabled=no, which must turn the OSC back on). tests/run.sh
-- reads the log.
local msg = require "mp.msg"

local function after(dt, fn) mp.add_timeout(dt, fn) end

mp.register_event("file-loaded", function()
    mp.commandv("script-message-to", "suji", "set-title", "Show", "Episode", "Name")
    msg.info("osc at start: " .. tostring(mp.get_property("osc")))
    after(0.2, function()
        mp.commandv("change-list", "script-opts", "append", "suji-scale=1.5")
        after(0.2, function()
            mp.commandv("change-list", "script-opts", "append", "suji-enabled=no")
            after(0.2, function()
                msg.info("osc when disabled: " .. tostring(mp.get_property("osc")))
                mp.commandv("quit")
            end)
        end)
    end)
end)
