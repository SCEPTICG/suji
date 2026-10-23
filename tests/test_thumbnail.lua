-- Thumbnails through thumbfast (core/thumbnail.lua), driven through main.lua
-- and the fake mp: what is sent to thumbfast and where, when it is taken
-- away, the line under the image and the time in the row.
local T = require "lib"

local function start(script_opts, hidpi)
    T.unload()
    mp = T.fake_mp({ ["mpv-version"] = "mpv v0.40.0" })
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = 1280, h = 720 })
    mp.fire("display-hidpi-scale", hidpi)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.fire("osd-font", "sans-serif")
    mp.mouse(0, 0)
    mp.advance(1)
end

-- What thumbfast says about itself.
local function info(t) mp.send("thumbfast-info", T.json(t)) end
local READY = { width = 200, height = 112, disabled = false, available = true }

-- The messages sent to thumbfast, as strings.
local function sent()
    local out = {}
    for _, c in ipairs(mp.commands) do
        if c[1] == "script-message-to" and c[2] == "thumbfast" then
            out[#out + 1] = table.concat(c, " ", 3)
        end
    end
    return out
end
local function last() local s = sent(); return s[#s] end

local function hover(x, y)
    mp.mouse(x, y or 645)
    mp.advance(0.5)
end
local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
-- The row's time at full opacity, and dimmed (the time under the cursor).
local function row_time(t) return painted():find("\\1a&H00&\\3a&H4D&\\4a&H99&}" .. t .. "{", 1, true) ~= nil end
local function row_dim(t) return painted():find("\\1a&H66&\\3a&H94&\\4a&HC2&}" .. t .. "{", 1, true) ~= nil end

-- Without thumbfast: nothing is sent, the row shows the time under the cursor
start()
hover(640)
T.eq(#sent(), 0, "no thumbfast: nothing sent")
T.check(row_dim("00:50"), "no thumbfast: the row shows the time under the cursor, dimmed")
hover(320)
T.check(row_dim("00:25"), "and follows the cursor")
T.check(not painted():find("\194\183", 1, true), "no box")

-- thumbfast says it cannot: still nothing
info({ width = 200, height = 112, disabled = true, available = false })
hover(640)
T.eq(#sent(), 0, "disabled: nothing sent")
for _, bad in ipairs({ { width = "x", height = 112 }, { width = 0, height = 112 }, { width = 99999, height = 112 },
                       { height = 112 }, "junk" }) do
    info(bad)
    hover(600)
    hover(640)
end
T.eq(#sent(), 0, "nonsense sizes: nothing sent")
mp.send("thumbfast-info", "{broken")
mp.send("thumbfast-info", ("x"):rep(5000))
hover(600)
T.eq(#sent(), 0, "broken or huge JSON: nothing sent")

-- thumbfast ready: centred on the cursor, just above the bar
-- Scale 1: 6 px around the image, a 20 px line under it, the box 212x144
-- with its bottom on the top of the bar's zone (y 634, the bar above the
-- row), 20 px from the window's sides.
info(READY)
mp.advance(0.1)
T.eq(last(), "thumb 46.875 500 496", "asked at once, for the cursor where it is")
hover(640)
T.eq(last(), "thumb 50.000 540 496", "centred: x 640 - 212 / 2 + 6, y 634 - 144 + 6")
local n = #sent()
mp.advance(1)
mp.mouse(640, 646) -- same x, same time
mp.advance(0.5)
T.eq(#sent(), n, "same time and place: no new message")
T.check(row_time("00:50"), "with a thumbnail the row shows the position")
T.check(not row_dim("00:50"), "not the time under the cursor")
local ass = painted()
T.check(ass:find("\\an5\\pos(640.0,618.0)", 1, true) ~= nil, "the time centred under the image")
T.check(ass:find("}00:50$") ~= nil or ass:find("}00:50\n", 1, true) ~= nil, "the time in the box")
T.check(not ass:find("\194\183", 1, true), "no chapters: only the time")
T.check(ass:find("\\1c&H000000&\\1a&H66&\\p3}m 2168 1960 ", 1, true) ~= nil, "the panel: black at 60%, from (534, 490)")
T.check(ass:find(" 2984 2504 b 2984 2522 2970 2536 2952 2536 ", 1, true) ~= nil, "to (746, 634), round corners")
hover(5)
T.eq(last(), "thumb 0.391 26 496", "left edge: inside the row's margin")
hover(1275)
T.eq(last(), "thumb 99.609 1054 496", "right edge: inside the row's margin")
hover(640)

-- Chapters: the one playing at that time, after the time
mp.fire("chapter-list", { { time = 0, title = "Intro" }, { time = 30, title = "Opening" }, { time = 60 } })
mp.advance(0.5)
T.check(painted():find("}00:50{\\1a&H66&\\3a&H94&\\4a&HC2&} \194\183 Opening", 1, true) ~= nil,
    "time, then the chapter, dimmed")
hover(320)
T.check(painted():find("} \194\183 Intro", 1, true) ~= nil, "another chapter")
hover(900)
T.check(not painted():find("\194\183", 1, true), "a chapter with no title: only the time")
mp.fire("chapter-list", { { time = 0, title = ("w"):rep(300) } })
hover(640)
local cut = painted():match("} \194\183 (w+)\226\128\166")
T.check(cut ~= nil, "a long chapter is cut")
T.check(cut and (5 + 3 + #cut + 1) * 13 * 0.55 <= 200, "to the image's width")
mp.fire("chapter-list", { { time = 0, title = "A\nB{\\c}" } })
hover(600)
T.check(painted():find("A?B\\{\\\226\128\139c\\}", 1, true) ~= nil, "a chapter is made printable and escaped")
mp.fire("chapter-list", nil)

-- Leaving the bar takes it away, once
hover(640)
n = #sent()
hover(150, 680) -- on the time, in the row
T.eq(last(), "clear", "leaving the bar: clear")
T.eq(#sent(), n + 1, "one message")
T.check(row_time("00:50"), "the row shows the position")
hover(640, 300)
T.eq(#sent(), n + 1, "no more clears")
mp.mouse(640, 645, false) -- out of the window, on the bar
hover(640)
mp.mouse(640, 645, false)
mp.advance(0.5)
T.eq(last(), "clear", "leaving the window: clear")
mp.advance(5)
T.eq(mp.active_timers(), 0, "no timers at rest")

-- Dragging: the box follows the cursor, out of the bar too
hover(640)
mp.button("down")
mp.mouse(800, 600)
mp.advance(0.1)
T.eq(last(), "thumb 62.500 700 496", "dragging: follows the cursor")
mp.mouse(1500, 600)
mp.advance(0.1)
T.eq(last(), "thumb 99.500 1054 496", "dragging past the edge: the seek target, at the edge")
mp.button("up")
mp.advance(0.5)
T.eq(last(), "clear", "let go off the bar: clear")

-- A change of file takes it away
hover(640)
mp.emit("end-file")
T.eq(last(), "clear", "end of file: clear")
mp.emit("file-loaded")
mp.advance(0.5)
T.eq(last(), "thumb 50.000 540 496", "the next file: asked again")

-- A menu opened over it takes it away
mp.send("open-menu", T.json({ type = "t", items = { { title = "a" } } }))
mp.advance(0.5)
T.eq(last(), "clear", "a menu open: clear")
T.check(row_dim("00:50"), "and the row shows the time under the cursor")
mp.send("close-menu")
hover(641)
T.eq(last(), "thumb 50.078 541 496", "menu closed: asked again")

-- thumbfast turned off for this file
info({ width = 200, height = 112, disabled = true, available = true })
mp.advance(0.5)
T.eq(last(), "clear", "disabled: clear")
info(READY)
mp.advance(0.5)
T.eq(last(), "thumb 50.078 541 496", "ready again: asked again")

-- thumbnails=no at run time, then yes
mp.set_opts({ thumbnails = false })
mp.advance(0.5)
T.eq(last(), "clear", "thumbnails=no: clear")
n = #sent()
hover(501)
T.eq(#sent(), n, "thumbnails=no: nothing sent")
T.check(row_dim("00:39"), "the row shows the time under the cursor")
mp.set_opts({ thumbnails = true })
mp.advance(0.5)
T.eq(last(), "thumb 39.141 401 496", "thumbnails=yes: asked again")

-- Turning suji off takes it away
mp.set_opts({ enabled = false })
T.eq(last(), "clear", "enabled=no: clear")
n = #sent()
hover(600)
T.eq(#sent(), n, "off: nothing sent")

-- thumbnails=no from the start: never a message
start({ thumbnails = false })
info(READY)
hover(640)
hover(100)
T.eq(#sent(), 0, "thumbnails=no: nothing sent")
mp.button("down")
mp.mouse(300, 600)
mp.advance(0.1)
mp.button("up")
T.eq(#sent(), 0, "nor while dragging")

-- HiDPI: thumbfast's size already has it, the box around grows with suji
start(nil, 2)
info(READY)
hover(640, 570) -- the bar's zone is 548 to 596 at scale 2
-- 12 px around, a 40 px line, the box 224x176 on y 548, 40 px margins.
T.eq(last(), "thumb 50.000 540 384", "HiDPI: the image keeps its size, the box grows")
hover(0, 570)
T.eq(last(), "thumb 0.000 52 384", "HiDPI: left margin 40 px")

-- A window too small for the box: no thumbnail, the row as before
start()
info(READY)
mp.fire("osd-dimensions", { w = 240, h = 720 })
hover(120)
T.eq(#sent(), 0, "no room: nothing sent")
T.check(row_dim("00:50") or not painted():find("00:50", 1, true), "no room: the row as before")

-- Drawn over an action button it covers, not under it
start()
info(READY)
mp.send("show-action", "skip-op", T.json({ text = "Skip opening \226\128\186", command = { "script-message-to", "fake", "skip-op" } }))
hover(1275)
local ass = painted()
local action, box = ass:find("}Skip opening", 1, true), ass:find("\\an5\\pos(1154.0,618.0)", 1, true)
T.check(action and box and box > action, "the box is painted after the action button")

-- available=false: thumbs are asked for (not disabled), clear is not sent
start()
info({ width = 200, height = 112, disabled = false, available = false })
hover(640)
T.eq(last(), "thumb 50.000 540 496", "not available: still asked (only disabled stops it)")
local before = #sent()
hover(150, 680)
T.eq(#sent(), before, "not available: no clear")
T.check(row_time("00:50"), "but the box is gone: the row shows the position")
info(READY)
hover(640)
hover(150, 680)
T.eq(last(), "clear", "available again: clear")

-- A failure in the thumbnail code leaves the rest of the frame
start()
info(READY)
hover(640)
package.loaded["core.thumbnail"].render = function() error("boom") end
hover(641)
local errors = 0
for _, l in ipairs(mp.logs) do if l[1] == "error" and tostring(l[2]):find("thumbnails failed", 1, true) then errors = errors + 1 end end
T.eq(errors, 1, "the failure is logged once")
T.eq(last(), "clear", "and the thumbnail taken away")
T.check(painted():find("}00:50{", 1, true) ~= nil, "the row still drawn")
before = #sent()
hover(300)
T.eq(#sent(), before, "turned off: nothing more sent")
T.check(row_dim("00:23"), "the row shows the time under the cursor again")

T.done("test_thumbnail")
