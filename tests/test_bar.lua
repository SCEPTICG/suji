local T = require "lib"
local bar = require "elements.bar"

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
T.eq(events(bar.render(st, 0, on)), 3, "rest: halo, rail, progress")
T.eq(events(bar.render(st, 1, on)), 5, "grown: plus knob and its halo")
T.eq(bar.render(st, 0, off), "", "idle_line=no draws nothing at rest")
T.eq(events(bar.render(st, 0.5, off)), 5, "idle_line=no still grows")
T.check(bar.render(st, 1, on):find("\\1c&H0000FF&", 1, true) ~= nil, "accent colour used")
T.eq(bar.render({ w = 1280, h = 720, scale = 1, time = 5 }, 1, on), "", "no duration, no bar")
T.eq(bar.render({ w = 0, h = 0, scale = 1, time = 5, duration = 10 }, 1, on), "", "no window")
T.check(bar.render(st, 1, on, 25) ~= bar.render(st, 1, on), "drag time moves the progress")

T.done("test_bar")
