-- Real test of the size in the more menu, loaded as a second script next
-- to suji in a virtual X display, twice (see tests/run.sh), with a state
-- folder of its own. Phase 1 opens more, picks Size and then 150%, and
-- checks that the row grew (user-data/suji/margins) and that the file
-- holds 150. Phase 2, a new mpv, checks that suji starts at 150%.
--
-- Window: 640x480 and the row pause,time,space,more,volume,fullscreen:
-- more is at x 408-452, on the row centred on y 440. Its menu ends 12 px
-- above the row's zones (y 406): Size is its last row, centred on y 391,
-- and so is 150%, the last of the sizes. The row's top is 62 px from the
-- bottom edge at 100%, 93 px at 150%.
--
-- xvfb_size-shot=<file> saves a screenshot with the sizes open, at 150%.

local msg = require "mp.msg"

local PHASE = mp.get_opt("xvfb_size-phase") or "1"
local SHOT = mp.get_opt("xvfb_size-shot")
local started, done = false, false
local bottom -- user-data/suji/margins.bottom

mp.observe_property("user-data/suji/margins", "native", function(_, m)
    bottom = type(m) == "table" and m.bottom or nil
end)

local function finish(ok, text)
    if done then return end
    done = true
    if ok then msg.info("xvfb-size: ok " .. text) else msg.error("xvfb-size: FAIL " .. text) end
    mp.commandv("quit", ok and "0" or "1")
end

local function file()
    local f = io.open(mp.command_native({ "expand-path", "~~state/suji-size" }), "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
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

if PHASE == "1" then
    after(0.3, function()
        if bottom ~= 62 then finish(false, "margins.bottom " .. tostring(bottom) .. " at start, not 62") end
        if file() ~= nil then finish(false, "the size file is there before any choice") end
    end)
    click_at(430, 440) -- more
    click_at(430, 391) -- Size
    click_at(430, 391) -- 150%
    after(0.5, function()
        if bottom ~= 93 then finish(false, "margins.bottom " .. tostring(bottom) .. " at 150%, not 93") end
        if file() ~= "150\n" then finish(false, ("the file holds %q"):format(tostring(file()))) end
        if mp.get_property_native("user-data/suji/menu/type") ~= "suji-more" then
            finish(false, "the menu closed after the choice")
        end
        if SHOT then mp.commandv("screenshot-to-file", SHOT, "window") end
    end)
    after(0.5, function() finish(true, "margins.bottom 62 at 100%, 93 at 150%, the file holds 150, the menu open") end)
else
    after(0.5, function()
        if bottom ~= 93 then finish(false, "margins.bottom " .. tostring(bottom) .. " on the next start, not 93") end
        if file() ~= "150\n" then finish(false, ("the file holds %q"):format(tostring(file()))) end
        finish(true, "the next start is at 150% (margins.bottom 93)")
    end)
end

mp.observe_property("osd-dimensions", "native", function(_, d)
    if started or type(d) ~= "table" or (d.w or 0) <= 0 then return end
    started = true
    run(1)
end)

mp.add_timeout(30, function() finish(false, "timed out") end)
