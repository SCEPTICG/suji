-- The controls option: parsing and conditions.
local T = require "lib"
local controls = require "core.controls"

local KNOWN = { pause = true, time = true, volume = true, fullscreen = true }
local warnings
local function parse(s)
    warnings = {}
    return controls.parse(s, KNOWN, function(w) warnings[#warnings + 1] = w end)
end
local function kinds(list)
    local t = {}
    for _, e in ipairs(list) do t[#t + 1] = e.kind == "module" and e.name or e.kind end
    return table.concat(t, ",")
end

-- Elements
T.eq(kinds(parse("pause,time,space,volume,fullscreen")), "pause,time,space,volume,fullscreen", "the default row")
T.eq(#warnings, 0, "no warnings for the default row")
T.eq(kinds(parse(" pause , gap,  time ,")), "pause,gap,time", "spaces and a trailing comma")
T.eq(kinds(parse("")), "", "empty")
T.eq(#controls.parse(nil, KNOWN, error), 0, "not a string")

-- command:icon:command?text
local c = parse("command:pause:cycle pause")[1]
T.eq(c.kind, "command", "command element")
T.eq(c.icon, "pause", "its icon")
T.eq(c.command, "cycle pause", "its command")
T.eq(c.text, nil, "no text")
c = parse("command:zap:script-binding x/open-menu?Open the menu")[1]
T.eq(c.command, "script-binding x/open-menu", "command before the ?")
T.eq(c.text, "Open the menu", "text after the ?")
c = parse("command:x:set pause yes?")[1]
T.eq(c.text, "", "an empty text")
T.eq(kinds(parse("command:x:show-text a:b")), "command", "colons inside the command")
T.eq(parse("command:x:show-text a:b")[1].command, "show-text a:b", "are kept")

-- Skipped, with one warning each, clean of control characters
T.eq(kinds(parse("pause,bogus,command:x,command::cmd,command:x: ?t,button:hikari,time")), "pause,time",
    "bad elements are skipped")
T.eq(#warnings, 5, "one warning per skipped element")
T.check(warnings[1]:find("'bogus'", 1, true) and warnings[1]:find("unknown", 1, true), "unknown element named")
T.check(warnings[4]:find("empty command", 1, true) ~= nil, "empty command")
T.check(warnings[5]:find("not supported yet", 1, true) ~= nil, "button: not yet")
parse("pause\27[31m,\7x,time")
T.eq(#warnings, 2, "control characters in names")
for _, w in ipairs(warnings) do
    T.check(not w:find("[%z\1-\31\127]"), "warning without control characters")
end
parse(("y"):rep(500))
T.check(#warnings[1] < 160, "a long bad element is cut in the warning")
T.eq(kinds(parse("pause:x,space:1,timeline,title")), "", "parameters where none go, layers")
T.eq(#warnings, 4, "each warned")

-- Conditions: commas inside <...> do not separate elements
local list = parse("<video,audio>pause,<has_chapter>time,space,< !idle + stream , has_playlist >volume,fullscreen")
T.eq(kinds(list), "pause,time,space,volume,fullscreen", "conditions do not split elements")
T.eq(#warnings, 0, "valid conditions")
T.eq(list[3].cond, nil, "no condition")
T.eq(kinds(parse("<a,b>command:x:set pause yes,time")), "command,time", "a command with a condition")
T.eq(kinds(parse("<a,b,time")), "", "unclosed < swallows the rest")
T.eq(#warnings, 1, "and is warned")
T.eq(kinds(parse("<>pause,<a,>time,<!>volume,<a+>fullscreen,<a b>pause,<!!a>pause")), "", "bad conditions")
T.eq(#warnings, 6, "each warned")

-- Evaluation: "!" binds tightest, then "+" (AND), then "," (OR)
local function holds(cond, values) return controls.eval(parse("<" .. cond .. ">pause")[1].cond, values) end
T.eq(holds("a", { a = true }), true, "a property that is true")
T.eq(holds("a", {}), false, "a missing property")
T.eq(holds("!a", {}), true, "negated")
T.eq(holds("a,b", { b = 1 }), true, "OR")
T.eq(holds("a+b", { a = true }), false, "AND")
T.eq(holds("a+b", { a = true, b = "x" }), true, "AND, both")
T.eq(holds("a,b+c", { a = true }), true, "a OR (b AND c): a alone")
T.eq(holds("a,b+c", { b = true }), false, "a OR (b AND c): b alone")
T.eq(holds("a+b,c", { c = true }), true, "(a AND b) OR c: c alone")
T.eq(holds("a+!b", { a = true, b = true }), false, "! binds tighter than +")
T.eq(holds("!a,b", { a = true }), false, "! binds tighter than ,")
T.eq(holds("user-data/x/on", { ["user-data/x/on"] = "yes" }), true, "user-data")
for _, v in ipairs({ false, "no", 0, "", {} }) do
    T.eq(holds("p", { p = v }), false, "false-like value: " .. tostring(v))
end
T.eq(holds("p", { p = { 1 } }), true, "a list with something in it")

-- Named conditions read their property
T.eq(holds("video", { ["current-tracks/video"] = { id = 1 } }), true, "video")
T.eq(holds("video", { ["current-tracks/video"] = { id = 1, albumart = true } }), false, "cover art is not video")
T.eq(holds("audio", { ["current-tracks/audio"] = { id = 1 } }), true, "audio")
T.eq(holds("audio", {}), false, "no audio")
T.eq(holds("stream", { ["demuxer-via-network"] = true }), true, "stream")
T.eq(holds("has_chapter", { chapters = 3 }), true, "has_chapter")
T.eq(holds("has_chapter", { chapters = 0 }), false, "no chapters")
T.eq(holds("has_playlist", { ["playlist-count"] = 2 }), true, "has_playlist")
T.eq(holds("has_playlist", { ["playlist-count"] = 1 }), false, "one file is not a playlist")
T.eq(holds("idle", { ["idle-active"] = true }), true, "idle")
local two = parse("<video+!pause,video>time,<video,user-data/a>pause,gap")
T.eq(table.concat(two[1].props, " "), "current-tracks/video pause", "properties to watch, once each")
T.eq(table.concat(two[2].props, " "), "current-tracks/video user-data/a", "per element")
T.eq(two[3].props, nil, "none without conditions")
-- Strings that mean false: set user-data/x 0 in input.conf gives "0"
for _, v in ipairs({ "0", "false" }) do
    T.eq(holds("p", { p = v }), false, "the string " .. v .. " is false")
end
T.eq(holds("p", { p = "1" }), true, "the string 1 is true")
T.eq(holds("p", { p = "yes" }), true, "yes is true")

-- Limits
local many = {}
for i = 1, 40 do many[i] = "gap" end
T.eq(#parse(table.concat(many, ",")), 32, "at most 32 elements")
T.eq(#warnings, 1, "warned once")
local long = "pause," .. ("gap,"):rep(2000)
T.eq(kinds(parse(long)):sub(1, 9), "pause,gap", "a long string still works")
T.check(warnings[1]:find("4096", 1, true) ~= nil, "longer than 4 KiB: cut and warned")
local cut = "time," .. (" "):rep(5000) .. "pause"
T.eq(kinds(parse(cut)), "time", "nothing is read past 4 KiB")
local half = "pause,time" .. (" "):rep(4080) .. ",fullscreen" -- the cut falls inside "fullscreen"
T.eq(kinds(parse(half)), "pause,time", "an element cut in half is dropped")
T.eq(#warnings, 1, "without a warning of its own")
local exact = "pause,time" .. (" "):rep(4086) .. ",fullscreen" -- byte 4097 is the comma
T.eq(kinds(parse(exact)), "pause,time", "a cut on a comma keeps the element before it")
T.eq(#("pause,time" .. (" "):rep(4086)), 4096, "(the cut is right before the comma)")

-- Long runs of spaces cost linear time
local t0 = os.clock()
for _ = 1, 20 do
    parse((" "):rep(4096))
    parse("pause" .. (" "):rep(4000) .. "x")
    parse("<" .. (" "):rep(4000) .. "a>pause")
    parse("command:x:" .. (" "):rep(4000) .. "?t")
end
T.check(os.clock() - t0 < 0.5, ("80 parses of 4 KiB of spaces take %.3f s"):format(os.clock() - t0))

T.done("test_controls")
