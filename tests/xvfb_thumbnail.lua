-- Thumbnails with a real mpv and the fake thumbfast (tests/fake/thumbfast.lua),
-- loaded next to suji in a virtual X display (see tests/run.sh). It moves
-- the mouse with input commands and reads what the fake got from suji in
-- user-data/fake-thumbfast: where it was asked for a thumbnail, and that
-- it was cleared off the bar, with suji turned off, with thumbnails=no and
-- on a change of file.
--
-- Window: 640x480 at scale 1, so the bar's zone starts at y 456. The fake
-- says 160x90: the box is 172x122 (6 px around the image, a 20 px line
-- under it), its bottom on y 456, so the image is at y 340; the row's
-- margins are 20 px. File: 60 s (59.9 to mpv), paused.

local msg = require "mp.msg"

local Y = 470 -- inside the bar zone
local started, done = false, false
local clears -- before the change of file

local function finish(ok, text)
    if done then return end
    done = true
    if ok then msg.info("xvfb-thumbnail: ok " .. text) else msg.error("xvfb-thumbnail: FAIL " .. text) end
    mp.commandv("quit", ok and "0" or "1")
end

local function got() return mp.get_property_native("user-data/fake-thumbfast") or {} end
local function expect(want, what)
    local last = got().last
    if last ~= want then finish(false, ("%s: got '%s', wanted '%s'"):format(what, tostring(last), want)) end
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
-- The message for the cursor at x, the image's left edge at ix.
local function thumb(x, ix)
    local t = mp.get_property_number("duration", 0) * x / 640
    return ("thumb %.3f %d 340"):format(t, ix)
end
local function mouse(x, y) mp.commandv("mouse", tostring(x), tostring(y)) end

after(0.5, function() mouse(320, 100) end)
after(0.3, function()
    if got().thumbs ~= 0 then finish(false, "asked for a thumbnail away from the bar") end
    mouse(320, Y)
end)
after(0.4, function()
    expect(thumb(320, 240), "centred")
    mouse(11, Y)
end)
after(0.4, function()
    expect(thumb(11, 26), "left edge")
    mouse(629, Y)
end)
after(0.4, function()
    expect(thumb(629, 454), "right edge")
    mouse(320, 300)
end)
after(0.4, function()
    expect("clear", "off the bar")
    mouse(320, Y)
end)
after(0.4, function()
    expect(thumb(320, 240), "back on the bar")
    mp.commandv("change-list", "script-opts", "append", "suji-enabled=no")
end)
after(0.4, function()
    expect("clear", "suji turned off")
    mp.commandv("change-list", "script-opts", "append", "suji-enabled=yes")
end)
after(0.4, function() mouse(300, Y) end)
after(0.4, function()
    expect(thumb(300, 220), "suji on again")
    mp.commandv("change-list", "script-opts", "append", "suji-thumbnails=no")
end)
after(0.4, function()
    expect("clear", "thumbnails=no")
    mouse(331, Y)
end)
after(0.4, function()
    expect("clear", "thumbnails=no, moving on the bar")
    mp.commandv("change-list", "script-opts", "append", "suji-thumbnails=yes")
end)
after(0.4, function()
    expect(thumb(331, 251), "thumbnails=yes")
    -- The same file again: end-file, then file-loaded.
    clears = got().clears
    mp.commandv("loadfile", mp.get_property("path"), "replace")
end)
-- The clear comes when the file changes, which takes a moment: wait for it,
-- at most 10 s.
after(0.1, function()
    local tries = 0
    local function check()
        if done then return end
        local g = got()
        if g.clears == clears + 1 then
            finish(true, ("%d thumbs, %d clears, last '%s'"):format(g.thumbs, g.clears, g.last))
        elseif (g.clears or 0) > clears + 1 then
            finish(false, "more than one clear on the change of file")
        elseif tries >= 100 then
            finish(false, "no clear on the change of file")
        else
            tries = tries + 1
            mp.add_timeout(0.1, check)
        end
    end
    check()
end)

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    run(1)
end)

mp.add_timeout(30, function() finish(false, "timed out") end)
