-- Real drag test, loaded as a second script next to suji in a virtual X
-- display (see tests/run.sh). It drives the mouse with input commands and
-- checks that dragging the bar seeks, that window dragging is only
-- switched off while the cursor is on the bar, and that real clicks reach
-- the pause button, the time (run.sh checks suji's debug line) and the
-- volume slider.
--
-- Window: 640x480, so suji's zone is y 456..479 and the row of controls is
-- centred on y 440. File: 60 s, paused.

local msg = require "mp.msg"

local W, H = 640, 480
local Y = 470                 -- inside the bar zone
local FROM, TO = 100, 480     -- drag from x=100 to x=480
local started, done = false, false

local function finish(ok, text)
    if done then return end
    done = true
    if ok then msg.info("xvfb-drag: ok " .. text) else msg.error("xvfb-drag: FAIL " .. text) end
    mp.commandv("quit", ok and "0" or "1")
end

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

after(0.5, function() mp.commandv("mouse", tostring(W / 2), "100") end)
after(0.3, function()
    if mp.get_property_bool("input-builtin-dragging") ~= true then
        finish(false, "window dragging is off away from the bar")
    end
    mp.commandv("mouse", tostring(FROM), tostring(Y))
end)
after(0.4, function()
    if mp.get_property_bool("input-builtin-dragging") ~= false then
        finish(false, "window dragging still on over the bar")
    end
    mp.commandv("keydown", "MBTN_LEFT")
end)
for x = FROM + 20, TO, 20 do
    after(0.03, function() mp.commandv("mouse", tostring(x), tostring(Y)) end)
end
after(0.2, function() mp.commandv("keyup", "MBTN_LEFT") end)
after(0.8, function()
    local t = mp.get_property_number("time-pos", -1)
    local want = 60 * TO / W
    if math.abs(t - want) > 1.5 then
        finish(false, ("time-pos %.2f, wanted about %.2f"):format(t, want))
    end
    mp.commandv("mouse", tostring(W / 2), "100")
end)
after(0.4, function()
    if mp.get_property_bool("input-builtin-dragging") ~= true then
        finish(false, "window dragging not restored after leaving the bar")
    end
    mp.commandv("mouse", "42", "436") -- the pause button
end)
after(0.4, function() mp.commandv("keypress", "MBTN_LEFT") end)
after(0.4, function()
    if mp.get_property_bool("pause") ~= false then finish(false, "pause button did not play") end
    mp.commandv("mouse", "100", "440") -- the time
end)
after(0.4, function() mp.commandv("keypress", "MBTN_LEFT") end)
after(0.4, function() mp.commandv("mouse", "536", "440") end) -- middle of the volume slider
after(0.4, function() mp.commandv("keypress", "MBTN_LEFT") end)
after(0.4, function()
    local v = mp.get_property_number("volume", -1)
    if v ~= 51 then finish(false, ("volume %s after a click on the slider"):format(v)) end
    finish(true, ("time-pos %.2f, pause, time and volume clicks"):format(mp.get_property_number("time-pos", -1)))
end)

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    run(1)
end)

mp.add_timeout(30, function() finish(false, "timed out") end)
