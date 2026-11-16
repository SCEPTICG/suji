-- Loaded after suji by tests/run.sh, in a 1280x1024 virtual display with a
-- 1280x720 video: picture in picture with a real mpv and a real window.
-- It enters and leaves with script-binding suji/pip and reads the window's
-- place and size with xwininfo each time. Inside, the window must be a
-- quarter of the screen's width, 320x180, 24 px from the right edge and 72
-- px from the bottom (936, 772); after, as it was before. Then the same
-- from fullscreen: it comes back fullscreen, and leaving fullscreen gives
-- the window of the start. It logs each step and "xvfb-pip: ok" at the
-- end; run.sh reads the log.
local msg = require "mp.msg"

local INSIDE, FULL = "320x180+936+772", "1280x1024+0+0"
local started, failed = false, false

-- The window as WxH+X+Y, from xwininfo, or nil.
local function geometry()
    local wid = mp.get_property_number("window-id")
    if not wid then return nil end
    local r = mp.command_native({ name = "subprocess", args = { "xwininfo", "-id", tostring(wid) },
                                  capture_stdout = true, playback_only = false })
    local out = type(r) == "table" and r.stdout or ""
    local x, y = out:match("Absolute upper%-left X:%s*(%-?%d+)"), out:match("Absolute upper%-left Y:%s*(%-?%d+)")
    local w, h = out:match("Width:%s*(%d+)"), out:match("Height:%s*(%d+)")
    if x and y and w and h then return ("%sx%s+%s+%s"):format(w, h, x, y) end
end

local function check(cond, what)
    if not cond then
        failed = true
        msg.info("xvfb-pip: FAIL " .. what)
    end
end

local function prop(name) return mp.get_property_native(name) end

-- Log the window and check it is want, with pip, ontop, border and
-- fullscreen as given.
local function expect(step, want, pip, ontop, border, fullscreen)
    local g = geometry()
    msg.info(("%s: %s, pip %s, ontop %s, border %s, fullscreen %s"):format(step, tostring(g),
        tostring(prop("user-data/suji/pip")), tostring(prop("ontop")), tostring(prop("border")),
        tostring(prop("fullscreen"))))
    check(g == want, ("%s: %s, want %s"):format(step, tostring(g), tostring(want)))
    check(prop("user-data/suji/pip") == pip, step .. ": user-data/suji/pip is not " .. tostring(pip))
    check(prop("ontop") == ontop, step .. ": ontop is not " .. tostring(ontop))
    check(prop("border") == border, step .. ": border is not " .. tostring(border))
    check(prop("fullscreen") == fullscreen, step .. ": fullscreen is not " .. tostring(fullscreen))
    return g
end

-- Each step runs, then the next one 1.5 s later.
local function steps(list)
    local i = 0
    local function go()
        i = i + 1
        if list[i] then
            list[i]()
            mp.add_timeout(1.5, go)
        end
    end
    go()
end

local before
local function key() mp.commandv("script-binding", "suji/pip") end

local function run()
    before = geometry()
    check(before and before:match("^1280x720%+"), "the window does not start at 1280x720: " .. tostring(before))
    steps({
        function() expect("before", before, false, false, true, false); key() end,
        function() expect("inside", INSIDE, true, true, false, false); key() end,
        function() expect("after", before, false, false, true, false); mp.set_property_bool("fullscreen", true) end,
        function() expect("fullscreen", FULL, false, false, true, true); key() end,
        function() expect("inside from fullscreen", INSIDE, true, true, false, false); key() end,
        function() expect("fullscreen again", FULL, false, false, true, true); mp.set_property_bool("fullscreen", false) end,
        function()
            expect("windowed", before, false, false, true, false)
            if not failed then
                msg.info(("xvfb-pip: ok %s, then %s inside and back; from fullscreen too"):format(before, INSIDE))
            end
            mp.commandv("quit")
        end,
    })
end

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    mp.add_timeout(1, run)
end)

mp.add_timeout(40, function()
    msg.info("xvfb-pip: FAIL timed out")
    mp.commandv("quit")
end)
