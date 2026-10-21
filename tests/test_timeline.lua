local T = require "lib"
local bar = require "modules.timeline"

-- Position <-> time
T.eq(bar.time_to_x(50, 100, 1000), 500, "middle")
T.eq(bar.time_to_x(-5, 100, 1000), 0, "before start clamps")
T.eq(bar.time_to_x(500, 100, 1000), 1000, "after end clamps")
T.eq(bar.time_to_x(nil, 100, 1000), 0, "unknown time")
T.eq(bar.time_to_x(10, 0, 1000), 0, "zero duration")
T.eq(bar.x_to_time(250, 100, 1000), 25, "quarter")
T.eq(bar.x_to_time(-20, 100, 1000), 0, "left of window")
T.eq(bar.x_to_time(5000, 100, 1000), 100, "right of window")
T.eq(bar.x_to_time(10, 100, 0), 0, "no window")
T.near(bar.x_to_time(bar.time_to_x(37.5, 120, 1920), 120, 1920), 37.5, "round trip")
T.eq(bar.progress_px(7200 * 4 / 1920 - 0.01, 7200, 1920), 3, "whole pixels only")
T.eq(bar.progress_px(7200 * 4 / 1920, 7200, 1920), 4, "next pixel")

T.eq(bar.seek_target(1000, 100, 1000), 99.5, "seek target stops short of the end")
T.eq(bar.seek_target(500, 100, 1000), 50, "seek target elsewhere is unchanged")
T.eq(bar.seek_target(1000, 0.2, 1000), 0, "very short file: never below 0")
T.eq(bar.time_to_x(5, 1 / 0, 1000), 0, "infinite duration")

-- Layout follows visibility
local g0 = bar.layout(1280, 720, 1, 0)
T.eq(g0.y1 - g0.y0, 2, "2 px at rest")
T.eq(g0.y1, 720, "rest line sits on the bottom edge")
local g1 = bar.layout(1280, 720, 1, 1)
T.eq(g1.y1 - g1.y0, 5, "5 px fully grown")
T.eq(g1.y1, 714, "grown line is lifted")
T.eq(g1.knob_r, 6.5, "13 px knob")
local g2 = bar.layout(2560, 1440, 2, 1)
T.eq(g2.y1 - g2.y0, 10, "HiDPI doubles the height")
local gx = bar.layout(1280, 720, 1, 7)
T.eq(gx.y1 - gx.y0, 5, "visibility above 1 is clamped")
local gh = bar.layout(1280, 720, 1, 0.5)
T.eq(gh.y1 - gh.y0 == math.floor(gh.y1 - gh.y0), true, "heights are whole pixels")

-- Zone
T.eq(bar.zone_top(720, 1), 696, "24 px zone")
T.eq(bar.zone_top(1440, 2), 1392, "zone scales")
T.check(bar.in_zone(10, 700, 1280, 720, 1), "inside zone")
T.check(not bar.in_zone(10, 690, 1280, 720, 1), "above zone")
T.check(not bar.in_zone(-1, 700, 1280, 720, 1), "left of window")

-- Rendering
local st = { w = 1280, h = 720, scale = 1, time = 50, duration = 100 }
local on = { idle_line = true, accent = "ff0000" }
local off = { idle_line = false, accent = "ff0000" }
local function events(s) local _, n = s:gsub("\n", ""); return s == "" and 0 or n + 1 end
T.eq(events(bar.ass(st, 0, on)), 3, "rest: halo, rail, progress")
T.eq(events(bar.ass(st, 1, on)), 5, "grown: plus knob and its halo")
T.eq(bar.ass(st, 0, off), "", "idle_line=no draws nothing at rest")
T.eq(events(bar.ass(st, 0.5, off)), 5, "idle_line=no still grows")
T.check(bar.ass(st, 1, on):find("\\1c&H0000FF&", 1, true) ~= nil, "accent colour used")
T.eq(bar.ass({ w = 1280, h = 720, scale = 1, time = 5 }, 1, on), "", "no duration, no bar")
T.eq(bar.ass({ w = 0, h = 0, scale = 1, time = 5, duration = 10 }, 1, on), "", "no window")
T.check(bar.ass(st, 1, on, 25) ~= bar.ass(st, 1, on), "drag time moves the progress")


-- Cached range
local ranges = { { start = 0, ["end"] = 10 }, { start = 40, ["end"] = 70 }, { start = 45, ["end"] = 60 } }
T.eq(bar.cached_until(ranges, 50), 70, "range around the position")
T.eq(bar.cached_until(ranges, 20), nil, "position outside every range")
T.eq(bar.cached_until(nil, 50), nil, "no cache state")
T.eq(bar.cached_until({ "junk", { start = "x" } }, 5), nil, "malformed ranges")
T.eq(bar.cached_until(ranges, nil), nil, "unknown position")

-- Chapter marks
local xs = bar.chapter_xs({ { time = 0 }, { time = 25 }, { time = 150 }, { time = -3 }, {}, "x" }, 100, 1000)
T.eq(#xs, 1, "only chapters inside the file, none at 0")
T.eq(xs[1], 250, "chapter x")
T.eq(#bar.chapter_xs({}, 100, 1000), 0, "empty list")
local many = {}
for i = 1, 30000 do many[i] = { time = i / 300 } end
T.eq(#bar.chapter_xs(many, 100, 1000), 500, "at most 500 marks")
T.eq(#bar.chapter_xs(many, 100, 1000, 4), 250, "at most one mark every 4 px")
T.eq(#bar.chapter_xs({ { time = 10 }, { time = 10.1 }, { time = 30 } }, 100, 1000, 4), 2, "close chapters share a mark")
T.check(bar.chapter_xs(many, 100, 1000) == bar.chapter_xs(many, 100, 1000), "same list: last result reused")
T.check(bar.chapter_xs(many, 100, 1000) ~= bar.chapter_xs(many, 100, 1000, 4), "another spacing: walked again")
-- 30000 chapters: never more than 500 marks, spread to the end of the bar
local lots = {}
for i = 1, 30000 do lots[i] = { time = i * 100 / 30001 } end
for _, g in ipairs({ { 3840, 1 }, { 3840, 0.25 }, { 1280, 0.25 } }) do
    local w, s = g[1], g[2]
    local marks = bar.chapter_xs(lots, 100, w, 2 * bar.MARK_WIDTH * s)
    local last = 0
    for _, x in ipairs(marks) do last = math.max(last, x) end
    T.check(#marks <= 500 and #marks >= 450, ("%d px, scale %s: %d marks, at most 500"):format(w, s, #marks))
    T.check(last > w * 0.98, ("%d px, scale %s: the last mark at %.0f, near the end"):format(w, s, last))
end
local five = {}
for i = 1, 5000 do five[i] = { time = i * 7200 / 5001 } end
for _, g in ipairs({ { 1920, 1 }, { 3840, 1 }, { 3840, 2 } }) do
    local big = { w = g[1], h = 1080 * g[2], scale = g[2], time = 50, duration = 7200 }
    local ass = bar.ass(big, 1, on, nil, nil, five)
    T.check(#ass < 32768, ("5000 chapters at %d px, scale %d: %d bytes, well under 64 KiB"):format(g[1], g[2], #ass))
end
T.eq(#bar.chapter_xs(nil, 100, 1000), 0, "no list")
T.eq(#bar.chapter_xs({ { time = 5 } }, nil, 1000), 0, "no duration")
local NAN = 0 / 0
local function finite(xs)
    for _, x in ipairs(xs) do if x ~= x or x == math.huge or x == -math.huge then return false end end
    return true
end
T.eq(#bar.chapter_xs({ { time = 5 } }, 0, 1000), 0, "duration 0")
T.eq(#bar.chapter_xs({ { time = 5 } }, NAN, 1000), 0, "duration NaN")
T.check(finite(bar.chapter_xs({ { time = NAN }, { time = "nan" }, { time = 5 } }, 100, 1000)), "a NaN chapter time")
T.eq(#bar.chapter_xs({ { time = NAN }, { time = 5 } }, 100, 1000), 1, "is left out")
T.eq(#bar.chapter_xs({ { time = 5 } }, 100, NAN), 0, "a NaN width: no marks")
T.check(finite(bar.chapter_xs({ { time = 5 }, { time = 50 } }, 100, 1000, NAN)), "a NaN spacing")
T.eq(#bar.chapter_xs({ { time = 5 }, { time = 50 } }, 100, 1000, NAN), 2, "keeps the marks")

local full = { w = 1280, h = 720, scale = 1, time = 50, duration = 100,
               cache_ranges = { { start = 40, ["end"] = 80 } }, chapters = { { time = 0 }, { time = 30 } } }
T.eq(events(bar.ass(full, 1, on, nil, full.cache_ranges, full.chapters)), 7, "grown: plus cache and chapter marks")
T.eq(events(bar.ass(full, 0, on, nil, full.cache_ranges, full.chapters)), 3, "at rest: no cache and no marks")
T.check(bar.ass(full, 1, on, nil, full.cache_ranges, full.chapters):find("\\1a&HD1&", 1, true) ~= nil, "cache at 18 %")

T.done("test_timeline")
