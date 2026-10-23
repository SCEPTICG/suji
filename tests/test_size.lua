-- The size in the more menu (core/size.lua and modules/more.lua): the
-- list, the change at once, the file in the state folder or the config
-- folder and when it is written. Every test that touches the disk uses a folder of its own.
local T = require "lib"

local W, H = 1280, 720
local NAME = "suji-size"

local base = os.tmpname()
os.remove(base)
local n_dirs = 0
-- A new empty folder.
local function folder()
    n_dirs = n_dirs + 1
    local d = ("%s/%d"):format(base, n_dirs)
    os.execute(("mkdir -p '%s'"):format(d))
    return d
end
local function put(dir, s)
    local f = assert(io.open(dir .. "/" .. NAME, "wb"))
    f:write(s)
    f:close()
end
local function get(dir)
    local f = io.open(dir .. "/" .. NAME, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- io.open is counted: opens[mode] for the file of the size and its .tmp.
local real_open = io.open
local opens
local function count_opens()
    opens = { r = 0, w = 0 }
    io.open = function(p, mode)
        if type(p) == "string" and (p:sub(-#NAME) == NAME or p:sub(-#NAME - 4) == NAME .. ".tmp") then
            local k = (mode or "r"):sub(1, 1)
            opens[k] = (opens[k] or 0) + 1
        end
        return real_open(p, mode)
    end
end

local function start(state_dir, script_opts, home_dir)
    T.unload()
    count_opens()
    local props = { ["mpv-version"] = "mpv v0.40.0", ["osd-dimensions"] = { w = W, h = H }, duration = 100,
                    pause = true, ["time-pos"] = 50, volume = 100,
                    ["track-list"] = { { type = "video", id = 1, selected = true } } }
    mp = T.fake_mp(props)
    mp.async_observe = true
    mp.state_dir, mp.home_dir = state_dir, home_dir
    mp.script_opts = script_opts
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = W, h = H })
    mp.fire("display-hidpi-scale", nil)
    mp.fire("duration", 100)
    mp.fire("pause", true)
    mp.fire("track-list", props["track-list"])
    mp.mouse(640, 300)
    mp.advance(1)
    return mp
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end
local function mod(name) return package.loaded["modules." .. name] end
local function menu() return package.loaded["core.menu"] end
local function scale() return package.loaded["core.state"].scale end
local function box_of(name)
    local l = package.loaded["core.layout"]
    return l.find(l.current(), mod(name))
end
local function warnings()
    local t = {}
    for _, l in ipairs(mp.logs) do
        if l[1] == "warn" and tostring(l[2]):find("^size:") then t[#t + 1] = l[2] end
    end
    return t
end
local function click(x, y)
    mp.mouse(x, y)
    mp.button("press")
    mp.advance(1)
end
local function open_more()
    local b = assert(box_of("more"), "more is in the row")
    click((b.x0 + b.x1) / 2, b.cy)
end
-- Centre of row k of n in the open more menu, at the scale of now: its
-- bottom is 12 px above the timeline's zone.
local function row(k, n)
    local s, b = scale(), box_of("more")
    local y1 = package.loaded["core.layout"].bar_zone().y0 - 12 * s
    return b.x0 + 40 * s, y1 - n * 30 * s + (k - 0.5) * 30 * s
end
-- y in px of the top of each active mark: the accent lines 2 px wide at
-- scale 1.
local function marks()
    local t = {}
    for x0, y0, x1 in painted():gmatch("\\1c&HFFFFFF&\\1a&H00&\\p3}m (%d+) (%d+) l (%d+)") do
        if math.abs(tonumber(x1) - tonumber(x0) - 8 * scale()) < 1 then t[#t + 1] = tonumber(y0) / 4 end
    end
    return t
end
-- Top in px of the highlighted row, nil when none.
local function highlight()
    local y = painted():match("\\1c&HFFFFFF&\\1a&HE6&\\p3}m %d+ (%d+)")
    return y and tonumber(y) / 4
end

-- No folders (mpv --no-config: ~~state/ and ~~home/ expand to "") ----------------------------
start(nil)
T.eq(scale(), 1, "100%")
T.eq(opens.r + opens.w, 0, "nothing read")
open_more()
local p = painted()
T.check(p:find("}Size", 1, true) and p:find("}100%", 1, true), "Size, with 100% on its right")
click(row(1, 1)) -- Size: the only item (one video track, no editions, no clipboard)
T.check(menu().is_open(mod("more")), "Size keeps the menu open")
p = painted()
T.check(p:find("}Size", 1, true) and p:find("}75%", 1, true) and p:find("}150%", 1, true), "the sizes, with a title")
T.eq(#marks(), 1, "one marked")
click(row(6, 6)) -- 150%
T.eq(scale(), 1.5, "150% at once")
T.eq(opens.w, 0, "no folders: nothing written")
T.eq(#warnings(), 0, "and nothing to warn about")
start("relative/dir", nil, "relative/home")
open_more()
click(row(1, 1))
click(row(6, 6))
T.eq(opens.r + opens.w, 0, "relative folders are never used")

-- Reading ------------------------------------------------------------------------------------------------------
local dir = folder()
start(dir)
T.eq(scale(), 1, "no file: 100%")
T.eq(opens.r, 0, "a missing file is not even opened")
T.eq(#warnings(), 0, "a missing file is not worth a warning")
for _, c in ipairs({ { "150\n", 1.5 }, { "75", 0.75 }, { " 110 \r\n", 1.1 } }) do
    put(dir, c[1])
    start(dir)
    T.near(scale(), c[2], ("%q is read"):format(c[1]))
    T.eq(opens.r, 1, ("%q: read once"):format(c[1]))
    T.eq(#warnings(), 0, ("%q: no warning"):format(c[1]))
end
for _, bad in ipairs({ "", "abc", "80", "150 150", "1.5", "-100", ("1"):rep(100), "150\0" }) do
    put(dir, bad)
    start(dir)
    T.eq(scale(), 1, ("%q: 100%%"):format(bad))
    T.eq(#warnings(), 1, ("%q: one warning"):format(bad))
end
local as_dir = folder()
os.execute(("mkdir '%s/%s'"):format(as_dir, NAME))
start(as_dir)
T.eq(scale(), 1, "unreadable (a folder): 100%")
T.eq(#warnings(), 1, "one warning")

-- With the scale option: 100% is scale, and the range still holds
put(dir, "125")
start(dir, { scale = 1.2 })
T.near(scale(), 1.5, "scale=1.2 at 125%: 1.5")
mp.fire("display-hidpi-scale", 2)
T.near(scale(), 3, "the HiDPI scale on top")
put(dir, "150")
start(dir, { scale = 8 })
T.eq(scale(), 8, "scale=8 at 150%: still 8")
put(dir, "75")
start(dir, { scale = 0.25 })
T.eq(scale(), 0.25, "scale=0.25 at 75%: still 0.25")
mp.set_opts({ scale = 2 })
T.near(scale(), 1.5, "the option changed at run time: 2 at 75%")

-- The menu and writing ---------------------------------------------------------------------------------------------
dir = folder()
start(dir)
mp.mouse(100, 600)
mp.advance(30)
mp.mouse(640, 300)
mp.fire("time-pos", 60)
mp.set_opts({ hide_delay = 2 })
mp.advance(30)
T.eq(opens.w, 0, "at rest, moving and with an option changed: nothing written")
T.eq(mp.active_timers(), 0, "no timers at rest")
local width = box_of("more").x1 - box_of("more").x0
open_more()
T.eq(opens.w, 0, "opening the menu writes nothing")
click(row(1, 1)) -- Size
T.eq(opens.w, 0, "neither does Size")
local x, y = row(6, 6)
T.eq(highlight(), y - 15, "the highlight is on the row under the mouse (150%), not on Size's index")
T.eq(marks()[1], select(2, row(3, 6)) - 7, "100% marked")
local commands = #mp.commands
x, y = row(5, 6)
click(x, y) -- 125%
T.near(scale(), 1.25, "125% at once")
local top = highlight()
T.check(top and top <= y and y < top + 30 * 1.25, "the highlight is on the row under the mouse in the bigger menu")
T.eq(#mp.commands, commands, "no mpv command")
T.near(box_of("more").x1 - box_of("more").x0, width * 1.25, "the row grew")
T.check(menu().is_open(mod("more")), "the menu stays open")
T.eq(#marks(), 1, "one marked")
T.near(marks()[1], select(2, row(5, 6)) - 7 * 1.25, "the mark moved to 125%", 0.5)
T.eq(get(dir), "125\n", "written: the number and nothing else")
T.eq(opens.w, 1, "written once")
x, y = row(1, 6)
mp.mouse(x, y)
mp.advance(1)
T.near(highlight(), y - 15 * 1.25, "the menu follows the new scale under the mouse", 0.5)
click(row(1, 6)) -- 75%
T.near(scale(), 0.75, "75%")
T.eq(get(dir), "75\n", "the new size written")
T.eq(opens.w, 2, "once per choice")
local two = { { type = "video", id = 1 }, { type = "video", id = 2 } }
mp.props["track-list"] = two
mp.fire("track-list", two)
mp.advance(0.1)
T.check(painted():find("}150%", 1, true) and not painted():find("}Video", 1, true), "a new track list: still the sizes")
mp.advance(60)
T.eq(opens.w, 2, "and never at rest")
T.eq(mp.active_timers(), 0, "no timers with the menu open either")
mp.bindings["suji-menu-esc"].fn()
mp.advance(1)
T.check(not menu().is_open(), "Esc closes it")
open_more()
p = painted()
T.check(p:find("}Size", 1, true) and p:find("}75%", 1, true) and not p:find("}150%", 1, true),
    "opened again: the first list, with 75%")
mp.mouse(10, 10)
mp.button("press") -- a click outside closes it
mp.advance(1)
T.check(not menu().is_open(), "a click outside closes it")
start(dir)
T.near(scale(), 0.75, "the next start reads it")
T.eq(opens.w, 0, "and writes nothing")

-- The state folder, else the config folder ------------------------------------------------------------------------
local state, home = folder(), folder()
put(home, "125")
start(state, nil, home)
T.near(scale(), 1.25, "only in the config folder: read there")
put(state, "90")
start(state, nil, home)
T.near(scale(), 0.9, "in both: the state folder's")
start(state, nil, base .. "/missing")
T.near(scale(), 0.9, "only in the state folder")
os.remove(state .. "/" .. NAME)
start(state, nil, home)
open_more()
click(row(1, 1))
click(row(6, 6))
T.eq(get(state), "150\n", "the state folder exists: written there")
T.eq(get(home), "125", "the config folder's is left alone")
start(state, nil, home)
T.eq(scale(), 1.5, "and the size written is the one read")
home = folder()
start(base .. "/no-state", nil, home)
open_more()
click(row(1, 1))
click(row(5, 6))
T.eq(get(home), "125\n", "no state folder: written in the config folder")
T.eq(#warnings(), 0, "without a warning")
start(base .. "/no-state", nil, home)
T.near(scale(), 1.25, "and read from there")

-- The keys: Enter on Size puts the cursor on the current size ------------------------------------------------------
start(nil)
open_more()
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-enter"].fn()
mp.advance(1)
T.eq(highlight(), select(2, row(3, 6)) - 15, "on 100%, the third")
mp.bindings["suji-menu-down"].fn()
mp.bindings["suji-menu-enter"].fn()
mp.advance(1)
T.near(scale(), 1.1, "Down and Enter: 110%")
T.near(highlight(), select(2, row(4, 6)) - 15 * 1.1, "the cursor stays on it", 0.5)

-- A double click on a size: the first click resizes the menu under the
-- cursor, and the second, on another row or off the menu, does nothing
for k, n in ipairs({ 0.75, 0.9, 1, 1.1, 1.25, 1.5 }) do
    start(nil)
    open_more()
    click(row(1, 1))
    mp.mouse(row(k, 6))
    mp.button("press")
    mp.advance(0.05)
    mp.button("press")
    mp.advance(1)
    T.near(scale(), n, ("a double click on %g%%: %g%%"):format(n * 100, n * 100))
    T.check(menu().is_open(mod("more")), ("%g%%: the menu stays open"):format(n * 100))
end
-- Nor on Size: the second click does not choose a size
start(nil)
open_more()
mp.mouse(row(1, 1))
mp.button("press")
mp.advance(0.05)
mp.button("press")
mp.advance(1)
T.eq(scale(), 1, "a double click on Size: the sizes, none chosen")
T.check(painted():find("}150%", 1, true) ~= nil, "and the sizes are open")

-- Not a regular file: a FIFO is never opened (it would block), a symbolic
-- link is replaced, not followed ------------------------------------------------------------------------------------
local fifo = folder()
os.execute(("mkfifo '%s/%s'"):format(fifo, NAME))
start(fifo)
T.eq(scale(), 1, "a FIFO: 100%")
T.eq(opens.r, 0, "not opened")
T.eq(#warnings(), 1, "one warning")
open_more()
click(row(1, 1))
click(row(5, 6))
T.near(scale(), 1.25, "a size still applies")
T.eq(opens.w, 0, "nothing written over it")
T.eq(#warnings(), 1, "still one warning")
fifo = folder()
os.execute(("mkfifo '%s/%s.tmp'"):format(fifo, NAME))
start(fifo)
open_more()
click(row(1, 1))
click(row(5, 6))
T.eq(opens.w, 0, "a FIFO as the .tmp: nothing written")
T.eq(#warnings(), 1, "one warning")
local link = folder()
put(link, "keep")
os.rename(link .. "/" .. NAME, link .. "/other")
os.execute(("ln -s other '%s/%s'"):format(link, NAME))
start(link)
T.eq(scale(), 1, "a link to a file with no size: read, 100%")
open_more()
click(row(1, 1))
click(row(5, 6))
local f = io.open(link .. "/other", "rb")
T.eq(f:read("*a"), "keep", "the file the link pointed to is left alone")
f:close()
T.eq(get(link), "125\n", "the size written")
local function test(flag, p)
    local r = os.execute(("test %s '%s'"):format(flag, p))
    return r == 0 or r == true
end
T.check(not test("-L", link .. "/" .. NAME) and test("-f", link .. "/" .. NAME), "suji-size is a regular file now")
T.eq(io.open(link .. "/" .. NAME .. ".tmp"), nil, "no .tmp left")
-- A symbolic link as the .tmp: removed, not followed
link = folder()
put(link, "keep")
os.rename(link .. "/" .. NAME, link .. "/victim")
os.execute(("ln -s victim '%s/%s.tmp'"):format(link, NAME))
start(link)
package.loaded["core.size"].set(110)
f = io.open(link .. "/victim", "rb")
T.eq(f:read("*a"), "keep", "the file the .tmp link pointed to is left alone")
f:close()
T.eq(get(link), "110\n", "the size written")
T.check(not test("-e", link .. "/" .. NAME .. ".tmp") and not test("-L", link .. "/" .. NAME .. ".tmp"), "no .tmp left")
-- A write that fails half way (a full disk): no .tmp left
dir = folder()
put(dir, "90")
start(dir)
local counted_open = io.open
io.open = function(p, mode)
    if mode == "wb" and p:sub(-4) == ".tmp" then
        local real = counted_open(p, mode)
        return { write = function(_, s) real:write(s:sub(1, 1)); return nil, "No space left on device" end,
                 close = function() return real:close() end }
    end
    return counted_open(p, mode)
end
package.loaded["core.size"].set(110)
io.open = counted_open
T.check(not test("-e", dir .. "/" .. NAME .. ".tmp"), "a failed write: no .tmp left")
T.eq(get(dir), "90", "the file is left as it was")
T.eq(#warnings(), 1, "one warning")
T.near(scale(), 1.1, "the size applies anyway")

-- Windows: no rename over a file that exists
local real_rename = os.rename
os.rename = function(a, b)
    if io.open(b) then return nil, "exists" end
    return real_rename(a, b)
end
dir = folder()
put(dir, "90")
start(dir)
open_more()
click(row(1, 1))
click(row(6, 6))
T.eq(get(dir), "150\n", "no rename over it: removed, then renamed")
-- Nor any rename at all: written in place
os.rename = function() return nil, "no" end
click(row(1, 6))
T.eq(get(dir), "75\n", "no rename: written in place")
T.eq(io.open(dir .. "/" .. NAME .. ".tmp"), nil, "no .tmp left")
T.eq(#warnings(), 0, "without a warning")
os.rename = real_rename

-- Cannot write: neither folder exists -------------------------------------------------------------------------------
start(base .. "/missing", nil, base .. "/missing-home")
open_more()
click(row(1, 1))
click(row(6, 6))
T.eq(scale(), 1.5, "the size applies anyway")
T.eq(#warnings(), 1, "one warning")
click(row(2, 6))
T.near(scale(), 0.9, "another size")
T.eq(#warnings(), 1, "still one warning")
T.check(menu().is_open(mod("more")), "and the menu is still open")

io.open = real_open
os.execute(("rm -rf '%s'"):format(base))
T.done("test_size")
