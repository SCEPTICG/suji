-- Real menu test, loaded as a second script next to suji in a virtual X
-- display (see tests/run.sh). The file has two audio tracks, two subtitle
-- tracks and three chapters, and plays paused. It opens the subtitles menu
-- with a click and picks the second track, opens the playlist menu and
-- picks the third chapter, then checks that a click outside a menu closes
-- it without seeking.
--
-- Window: 640x480, and the row run.sh gives it, with no more button. The
-- row is centred on y 440 and its right part is, from the right edge:
-- fullscreen, volume, speed, playlist (356-400), audio, subtitles
-- (252-296). A menu ends 12 px above the row's zones (y 406), with rows of
-- 30 px: the subtitles menu (Off, two tracks, and Load from clipboard with
-- mpv 0.40) starts at y 286 (316 without the clipboard), the playlist
-- menu (three chapters) at y 316.

local msg = require "mp.msg"

local started, done = false, false

-- Without the clipboard (mpv 0.39) the subtitles menu has one item less,
-- and its rows are 30 px lower.
local CLIP = 30
for _, p in ipairs(mp.get_property_native("property-list") or {}) do
    if p == "clipboard" then CLIP = 0 end
end

local function finish(ok, text)
    if done then return end
    done = true
    if ok then msg.info("xvfb-menu: ok " .. text) else msg.error("xvfb-menu: FAIL " .. text) end
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

-- Move there, wait for suji to bind the button, click.
local function click_at(x, y)
    after(0.3, function() mp.commandv("mouse", tostring(x), tostring(y)) end)
    after(0.3, function() mp.commandv("keypress", "MBTN_LEFT") end)
end

click_at(274, 440) -- the subtitles button
click_at(292, 361 + CLIP) -- third row: the second track
after(0.4, function()
    local sid = mp.get_property_number("sid")
    if sid ~= 2 then finish(false, ("sid %s after choosing the second track"):format(tostring(sid))) end
end)
click_at(378, 440) -- the playlist button
click_at(396, 391) -- third row: the third chapter
after(0.5, function()
    local chapter = mp.get_property_number("chapter")
    if chapter ~= 2 then finish(false, ("chapter %s after choosing the third"):format(tostring(chapter))) end
end)
local before
click_at(274, 440) -- the subtitles menu again
after(0.3, function() before = mp.get_property_number("time-pos") end)
click_at(100, 470) -- on the timeline, outside the menu
after(0.5, function()
    local t = mp.get_property_number("time-pos")
    if math.abs(t - before) > 0.01 then finish(false, ("a click outside the menu seeked to %.2f"):format(t)) end
end)
click_at(292, 331 + CLIP) -- where the first track was: the menu is gone, nothing happens
after(0.4, function()
    local sid = mp.get_property_number("sid")
    if sid ~= 2 then finish(false, "the click outside did not close the menu (sid " .. tostring(sid) .. ")") end
    finish(true, ("sid 2, chapter %d, time-pos %.2f"):format(mp.get_property_number("chapter"), mp.get_property_number("time-pos")))
end)

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    run(1)
end)

mp.add_timeout(30, function() finish(false, "timed out") end)
