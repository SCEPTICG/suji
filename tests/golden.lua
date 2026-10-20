-- Golden output: the ASS suji paints and what a click does at every
-- point of the row, for a fixed set of situations. It only drives main.lua
-- through the fake mp, so the same script runs on any version of suji.
-- tests/golden/v0.1.0.txt was made with it from v0.1.0 (see make_golden.lua);
-- test_golden.lua checks that the current code gives the same text.

local T = require "lib"

local function unload()
    for name in pairs(package.loaded) do
        if name == "main" or name:find("^core%.") or name:find("^modules%.") or name:find("^elements%.") or
            ({ options = 1, state = 1, draw = 1, animation = 1, painter = 1, mouse = 1, visibility = 1, icons = 1 })[name] then
            package.loaded[name] = nil
        end
    end
end

local function start(w, h, hidpi, script_opts)
    unload()
    mp = T.fake_mp({ ["mpv-version"] = "mpv v0.40.0" })
    mp.script_opts = script_opts or { debug = true }
    dofile("suji/main.lua")
    mp.fire("osd-dimensions", { w = w, h = h })
    mp.fire("display-hidpi-scale", hidpi)
    mp.fire("duration", 100)
    mp.fire("pause", false)
    mp.fire("time-pos", 50)
    mp.fire("osd-font", "sans-serif")
    mp.mouse(0, 0)
    mp.advance(1)
end

local function painted() return mp.updates[#mp.updates] and mp.updates[#mp.updates].data or "" end

-- What a click at (x, y) does: the command it sends, "time" for the time
-- (clicked twice, so the next point starts the same), "-" for nothing.
local function remaining_logs()
    local n = 0
    for _, l in ipairs(mp.logs) do if l[2] and tostring(l[2]):find("^remaining time") then n = n + 1 end end
    return n
end
local function click(x, y)
    mp.mouse(x, y)
    local bound = mp.bindings["suji-bar"] ~= nil
    local wheel = mp.bindings["suji-wheel-up"] ~= nil
    mp.commands = {}
    local before = remaining_logs()
    mp.button("press")
    local what = "-"
    if remaining_logs() > before then
        what = "time"
        mp.button("press")
    elseif #mp.commands > 0 then
        local c = mp.commands[#mp.commands]
        what = c[1] == "seek" and "seek" or table.concat(c, " ")
    end
    return (bound and "b" or "") .. (wheel and "w" or "") .. ":" .. what
end

-- Runs of the same result along a line: "x0-x1 result".
local function hit_line(out, y, w, step)
    local from, last
    local function flush(to)
        if last then out[#out + 1] = ("  y=%d x=%d-%d %s"):format(y, from, to, last) end
    end
    for x = 0, w - 1, step do
        local r = click(x, y)
        if r ~= last then flush(x - step); from, last = x, r end
    end
    flush(w - 1)
end

local function paint(out, name)
    mp.advance(1)
    out[#out + 1] = "== " .. name
    out[#out + 1] = painted()
end

return function()
    local out = {}
    for _, g in ipairs({ { 1280, 720, nil, 1 }, { 2560, 1440, 2, 2 } }) do
        local w, h, hidpi, s = g[1], g[2], g[3], g[4]
        local tag = ("%dx%d scale %d: "):format(w, h, s)

        start(w, h, hidpi)
        paint(out, tag .. "at rest")

        start(w, h, hidpi)
        mp.fire("media-title", "Movie")
        mp.fire("volume", 40)
        mp.fire("pause", true)
        paint(out, tag .. "paused")
        mp.mouse(math.floor(w / 4), h - 10 * s)
        paint(out, tag .. "on the timeline")
        mp.mouse(math.floor(w / 2), h - 300 * s)
        mp.fire("pause", false)
        mp.mouse(math.floor(w / 2), h - 100 * s)
        mp.advance(0.05)
        out[#out + 1] = "== " .. tag .. "half way"
        out[#out + 1] = painted()

        start(w, h, hidpi, { debug = true, remaining_time = true, accent = "ff8000" })
        mp.fire("pause", true)
        mp.fire("volume", 100)
        mp.fire("mute", true)
        mp.fire("fullscreen", true)
        mp.fire("chapter-list", { { time = 0 }, { time = 20 }, { time = 70 } })
        mp.fire("demuxer-cache-state", { ["seekable-ranges"] = { { start = 30, ["end"] = 80 } } })
        mp.messages["set-title"]("A Series", "An episode with a title long enough to be cut " .. ("x"):rep(200))
        paint(out, tag .. "remaining, muted, fullscreen, chapters, cache, two lines")

        start(w, h, hidpi)
        mp.fire("duration", 5000)
        mp.fire("time-pos", 4000)
        mp.fire("volume", 0)
        mp.fire("pause", true)
        mp.fire("media-title", "File.mkv")
        mp.fire("filename", "File.mkv")
        mp.fire("filename/no-ext", "File")
        paint(out, tag .. "long time, volume 0")

        start(w, h, hidpi)
        mp.fire("duration", nil)
        mp.fire("time-pos", nil)
        mp.fire("pause", true)
        paint(out, tag .. "no duration")

        -- Clicks along the row and at the edges of the zones.
        start(w, h, hidpi)
        mp.fire("volume", 100)
        mp.fire("pause", true)
        mp.advance(1)
        out[#out + 1] = "== " .. tag .. "clicks"
        local cy, half = h - 40 * s, 22 * s
        for _, y in ipairs({ cy - half - 1, cy - half, cy, cy + half - 1, h - 24 * s - 1, h - 24 * s }) do
            hit_line(out, y, w, s)
        end
    end
    return table.concat(out, "\n") .. "\n"
end
