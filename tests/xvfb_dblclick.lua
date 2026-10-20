-- Loaded next to suji by tests/xvfb_dblclick.sh, which clicks with real X
-- events (mpv's own keypress command never makes a double click). It logs
-- when the speed and fullscreen change, with the time, and quits after a
-- while; the shell script reads the log.
local msg = require "mp.msg"

local function report(name)
    mp.observe_property(name, "string", function(_, v)
        msg.info(("%s %s at %.2f"):format(name, tostring(v), mp.get_time()))
    end)
end
report("speed")
report("fullscreen")

mp.add_timeout(20, function() mp.commandv("quit") end)
